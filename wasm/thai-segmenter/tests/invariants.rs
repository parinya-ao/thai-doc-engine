// Properties the segmenter must hold for *any* input, plus the standing
// accuracy ratchet against the curated word list.
//
// The unit tests in src/lib.rs check specific sentences. These check invariants
// over the whole fixture, and record — as a number that may only go down — how
// far the shipped model still is from a dictionary segmenter's idea of a word.

use thai_segmenter::{cluster_count, phrase_boundaries, segment_str, weld_str};

const UNIT_SEPARATOR: char = '\u{1F}';
const WORD_JOINER: char = '\u{2060}';

/// Words a dictionary segmenter keeps whole. See the header of the fixture.
fn keep_phrases() -> Vec<&'static str> {
    include_str!("keep-phrases.txt")
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .collect()
}

fn chunks(text: &str, min_chunk: usize) -> Vec<String> {
    segment_str(text, min_chunk).split(UNIT_SEPARATOR).map(str::to_string).collect()
}

/// How many of the 300 curated words the shipped model splits when they appear
/// in running text.
///
/// This is a ratchet, not a target: lower it whenever the model improves, never
/// raise it. It is the acceptance gate for replacing models/th.json — a distilled
/// model earns its place by driving this number down, and the Typst package can
/// drop its runtime `keep-phrases` list once the number is low enough that the
/// list is no longer doing any work.
/// Measured against the vendored `models/th.json`: 268 of 300. The list was
/// selected as words this model splits, so a high number is expected — it is
/// here to be driven down, and to make the size of the gap visible.
const CURATED_WORDS_STILL_SPLIT: usize = 268;

/// Put the word somewhere the model has to make a real decision about it: Thai
/// context on both sides, of the kind `\p{sc=Thai}{8,}` in engine.typ matches.
fn in_context(word: &str) -> String {
    format!("ระบบนี้{word}ได้อย่างสมบูรณ์")
}

#[test]
fn curated_words_split_no_more_often_than_recorded() {
    let split: Vec<&str> = keep_phrases()
        .into_iter()
        .filter(|word| {
            // The word survives if it is wholly inside one chunk.
            !chunks(&in_context(word), 3).iter().any(|c| c.contains(word))
        })
        .collect();
    assert!(
        split.len() <= CURATED_WORDS_STILL_SPLIT,
        "{} of {} curated words are split, up from the recorded {CURATED_WORDS_STILL_SPLIT}: {:?}",
        split.len(),
        keep_phrases().len(),
        &split[..split.len().min(10)]
    );
}

#[test]
fn segmentation_is_lossless() {
    for word in keep_phrases() {
        let text = in_context(word);
        for min_chunk in [0, 2, 3, 4, 8] {
            let rejoined = segment_str(&text, min_chunk).replace(UNIT_SEPARATOR, "");
            assert_eq!(rejoined, text, "segment_str lost characters at min_chunk {min_chunk}");
            let unwelded = weld_str(&text, min_chunk).replace(WORD_JOINER, "");
            assert_eq!(unwelded, text, "weld_str lost characters at min_chunk {min_chunk}");
        }
    }
}

#[test]
fn boundaries_are_ascending_in_range_and_unique() {
    for word in keep_phrases() {
        let text = in_context(word);
        let len = text.chars().count();
        let cuts = phrase_boundaries(&text, 3);
        assert!(
            cuts.windows(2).all(|w| w[0] < w[1]),
            "boundaries out of order for {word}: {cuts:?}"
        );
        assert!(
            cuts.iter().all(|&c| c > 0 && c < len),
            "boundary outside 1..{len} for {word}: {cuts:?}"
        );
    }
}

#[test]
fn every_chunk_meets_the_cluster_minimum() {
    for word in keep_phrases() {
        let text = in_context(word);
        for min_chunk in [2usize, 3, 4] {
            let out = chunks(&text, min_chunk);
            // The last chunk is the one exception the merge cannot fix by
            // merging forwards, and it merges backwards instead -- so after the
            // pass, every chunk qualifies.
            assert!(
                out.iter().all(|c| cluster_count(c) >= min_chunk),
                "min_chunk {min_chunk} left a short chunk in {out:?}"
            );
        }
    }
}

#[test]
fn the_minimum_only_ever_removes_boundaries_the_model_found() {
    // The merge subtracts from the raw break set; it never proposes a position
    // of its own. Note that the sets across two *non-zero* minimums do not
    // nest: the merge is greedy from the left, so dropping an early cut moves
    // the measuring point and a later cut that was too close before can qualify
    // afterwards. That is correct -- the chunk it opens really does meet the
    // larger minimum -- so the invariant is against the raw set, not pairwise.
    for word in keep_phrases() {
        let text = format!("ใช้{}LoRa 920.5 MHz ได้", in_context(word));
        let raw = phrase_boundaries(&text, 0);
        for min_chunk in [2usize, 3, 4, 6, 8] {
            let cuts = phrase_boundaries(&text, min_chunk);
            assert!(
                cuts.iter().all(|c| raw.contains(c)),
                "min_chunk {min_chunk} invented a boundary: {cuts:?} not within {raw:?}"
            );
        }
    }
}
