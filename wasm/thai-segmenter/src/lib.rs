// BudouX phrase segmenter for Thai, exposed as a Typst WebAssembly plugin.
//
// Typst already breaks Thai at *word* boundaries through ICU's LSTM segmenter,
// so a line can end anywhere inside a phrase. This plugin supplies the missing
// information — where the *phrase* boundaries are — and `docs/template.typ`
// uses it to forbid the breaks that fall between them.
//
// The model is Google's `budoux/models/th.json` (Apache-2.0, see ../NOTICE) and
// the scoring below is a transcription of BudouX's `Parser.parse`: an AdaBoost
// ensemble whose features are unigrams over a six-character window plus the
// bigrams and trigrams straddling the candidate boundary. build.rs bakes the
// weights into sorted static tables; nothing is parsed at runtime.

// Only the wasm build wears the protocol: on the host target the crate stays a
// plain rlib so `cargo test` can exercise the segmenter directly.
#[cfg(target_arch = "wasm32")]
use wasm_minimal_protocol::wasm_func;

#[cfg(target_arch = "wasm32")]
wasm_minimal_protocol::initiate_protocol!();

include!(concat!(env!("OUT_DIR"), "/model.rs"));

/// Chunk separator in `segment`'s output. U+001F UNIT SEPARATOR is a control
/// character, so it cannot occur in the document text being segmented.
const UNIT_SEPARATOR: char = '\u{1F}';

/// U+2060 WORD JOINER — UAX #14 rule LB11 (`× WJ`, `WJ ×`) forbids a line break
/// at that position. Emitted by `weld` for `phrase-method: "wj"`.
const WORD_JOINER: char = '\u{2060}';

/// Characters that must never start a chunk.
///
/// U+0E30..=U+0E3A are the vowel signs and marks that follow their consonant
/// (ะ ั า ำ ิ ี ึ ื ุ ู ฺ), U+0E45..=U+0E4E adds ๅ, the repetition mark ๆ — which
/// belongs to the word it repeats — and the tone marks / thanthakhat. Breaking
/// before any of them splits a grapheme cluster and renders a dotted circle.
fn is_non_starter(c: char) -> bool {
    matches!(c, '\u{0E30}'..='\u{0E3A}' | '\u{0E45}'..='\u{0E4E}')
}

/// U+0E3A PHINTHU subscripts the consonant that *follows* it, in Pali and
/// Sanskrit spellings (พฺราหฺมณ). It is already covered by `is_non_starter`, so
/// nothing may break before it; `is_cluster_boundary` also forbids breaking
/// after it, which is what keeps the subscript attached to its base.
const PHINTHU: char = '\u{0E3A}';

/// Characters that must never end a chunk: the leading vowels เ แ โ ใ ไ, which
/// are written before the consonant they are pronounced after.
fn is_leading_vowel(c: char) -> bool {
    matches!(c, '\u{0E40}'..='\u{0E44}')
}

/// A decimal digit in either script the documents use — ASCII and Thai
/// (U+0E50..=U+0E59, ๐๑๒๓๔๕๖๗๘๙).
fn is_digit(c: char) -> bool {
    c.is_ascii_digit() || matches!(c, '\u{0E50}'..='\u{0E59}')
}

/// Whether a break at `i` would fall *inside* a token that is atomic no matter
/// what the model thinks: a run of ASCII alphanumerics (AVR128DA28, LoRa, SF7),
/// or a number with a decimal separator inside it (920.5, ๑,๐๐๐).
///
/// `is_script_transition` already keeps such a token from *merging* into the
/// Thai around it; this keeps the token from being split down the middle. The
/// shipped model happens never to cut these, but nothing in an n-gram model
/// guarantees that, and a model refresh could change it silently.
///
/// A veto, not a vote: `is_breakable` applies it before anything else, so not
/// even a forced boundary can override it. That matters where the two collide —
/// a Thai digit next to an ASCII one is a script transition *and* the middle of
/// a number, and staying whole is the right answer.
fn is_inside_token(chars: &[char], i: usize) -> bool {
    let (a, b) = (chars[i - 1], chars[i]);
    if a.is_ascii_alphanumeric() && b.is_ascii_alphanumeric() {
        return true;
    }
    if is_digit(a) && is_digit(b) {
        return true;
    }
    let separator = |c: char| c == '.' || c == ',';
    // 128|.5 — the separator opens the second chunk.
    if separator(b) && is_digit(a) && chars.get(i + 1).is_some_and(|&c| is_digit(c)) {
        return true;
    }
    // 128.|5 — the separator closes the first one.
    separator(a) && is_digit(b) && i >= 2 && is_digit(chars[i - 2])
}

/// Whether `chars[i]` begins a new orthographic cluster: it is not a mark that
/// hangs off the previous character, and the previous character is not one that
/// must stay glued to what follows it.
///
/// This is the same question as "may a chunk end here", which is why
/// `is_breakable` is this predicate plus bounds checks and the atomic-token
/// veto — a chunk boundary is by definition a cluster boundary.
fn is_cluster_boundary(chars: &[char], i: usize) -> bool {
    let previous = chars[i - 1];
    !is_non_starter(chars[i]) && !is_leading_vowel(previous) && previous != PHINTHU
}

/// Running count of cluster boundaries: `prefix[i]` is how many of `1..=i` begin
/// a cluster, so the clusters in `chars[a..b]` number `1 + prefix[b - 1] -
/// prefix[a]`. `merge_short_chunks` asks that question once per candidate cut,
/// which is why it is a prefix sum rather than a rescan.
fn cluster_prefix(chars: &[char]) -> Vec<u32> {
    let mut prefix = Vec::with_capacity(chars.len());
    prefix.push(0);
    for i in 1..chars.len() {
        prefix.push(prefix[i - 1] + u32::from(is_cluster_boundary(chars, i)));
    }
    prefix
}

/// Clusters in `chars[start..end]`, given `cluster_prefix(chars)`.
fn cluster_len(prefix: &[u32], start: usize, end: usize) -> usize {
    debug_assert!(start < end && end <= prefix.len());
    (1 + prefix[end - 1] - prefix[start]) as usize
}

/// Number of orthographic clusters in `text` — how many glyph stacks a reader
/// sees, which is the unit `min_chunk` counts. `ที่` is three characters but one
/// cluster; `หน้า` is four characters but two. Counting characters instead
/// overstates how wide a fragment looks by up to a factor of four.
pub fn cluster_count(text: &str) -> usize {
    let chars: Vec<char> = text.chars().collect();
    if chars.is_empty() {
        return 0;
    }
    cluster_len(&cluster_prefix(&chars), 0, chars.len())
}

/// Whether a break at `i` is *structurally* legal, independent of the model.
///
/// The trained weights already score the orthographic cases strongly negative
/// (`UW3["ั"] = -3075`), so that part rarely changes an answer — it turns a
/// statistical property into a guaranteed one. The whitespace and atomic-token
/// clauses are not in the weights at all.
fn is_breakable(chars: &[char], i: usize) -> bool {
    i > 0
        && i < chars.len()
        // A chunk that opens with a space would carry that space into a box,
        // where it can no longer be the break opportunity UAX #14 says it is.
        && !chars[i].is_whitespace()
        && is_cluster_boundary(chars, i)
        && !is_inside_token(chars, i)
}

/// Whether the break at `i` crosses from ASCII alphanumerics into the Thai
/// Unicode block (U+0E00..=U+0E7F) or vice versa — model numbers, unit
/// abbreviations and citation markers embedded in Thai prose (AVR128DA28,
/// LoRa, SF7) are never part of a BudouX phrase, so this is taken
/// unconditionally in `boundaries`, bypassing `is_phrase_boundary` entirely.
/// Alphanumerics only — ASCII punctuation/whitespace isn't a "script" and
/// would misfire around ordinary punctuation next to Thai text.
///
/// Always ANDed with `is_breakable` at every call site, so this can only
/// widen positions `is_breakable` already allows — it cannot split a
/// combining mark off its base character.
fn is_script_transition(chars: &[char], i: usize) -> bool {
    let is_thai = |c: char| matches!(c, '\u{0E00}'..='\u{0E7F}');
    let (a, b) = (chars[i - 1], chars[i]);
    (a.is_ascii_alphanumeric() && is_thai(b)) || (is_thai(a) && b.is_ascii_alphanumeric())
}

/// Boundaries taken without consulting the model, and never given back by the
/// short-chunk merge: a script transition, or the end of a run of whitespace.
///
/// The whitespace clause is the other half of the rule `is_breakable` starts —
/// no chunk may *open* with a space, so a chunk has to *close* on one. Together
/// they put the run of spaces at the tail of the preceding chunk, where a line
/// end can absorb it, instead of at the head of the following one, where a box
/// would freeze it.
fn is_forced_boundary(chars: &[char], i: usize) -> bool {
    is_script_transition(chars, i) || chars[i - 1].is_whitespace()
}

/// Fold `chars[start..end]` into the integer the model tables are keyed by: a
/// leading 1 bit, then each character in 21 bits, most significant first. The
/// mirror of `pack` in build.rs — see the comment there for why the tables hold
/// integers rather than strings.
fn pack(chars: &[char], start: usize, end: usize) -> u64 {
    chars[start..end].iter().fold(1u64, |acc, &c| (acc << 21) | c as u64)
}

/// Weight of the unigram `chars[i]`, or 0 when the model has never seen it.
fn uni(table: &phf::Map<u32, i32>, chars: &[char], i: usize) -> i64 {
    table.get(&(pack(chars, i, i + 1) as u32)).copied().unwrap_or(0) as i64
}

/// Weight of the bigram or trigram `chars[start..end]`.
fn multi(table: &phf::Map<u64, i32>, chars: &[char], start: usize, end: usize) -> i64 {
    table.get(&pack(chars, start, end)).copied().unwrap_or(0) as i64
}

/// BudouX's decision for the boundary before `chars[i]`, with `i > 0`.
///
/// Reference: `sum(weights) - 0.5 * TOTAL > 0`, rewritten as `2 * sum > TOTAL`.
fn is_phrase_boundary(chars: &[char], i: usize) -> bool {
    let n = chars.len();
    let mut sum: i64 = 0;

    if i > 2 {
        sum += uni(UW1, chars, i - 3);
    }
    if i > 1 {
        sum += uni(UW2, chars, i - 2);
    }
    sum += uni(UW3, chars, i - 1);
    sum += uni(UW4, chars, i);
    if i + 1 < n {
        sum += uni(UW5, chars, i + 1);
    }
    if i + 2 < n {
        sum += uni(UW6, chars, i + 2);
    }

    if i > 1 {
        sum += multi(BW1, chars, i - 2, i);
    }
    sum += multi(BW2, chars, i - 1, i + 1);
    if i + 1 < n {
        sum += multi(BW3, chars, i, i + 2);
    }

    if i > 2 {
        sum += multi(TW1, chars, i - 3, i);
    }
    if i > 1 {
        sum += multi(TW2, chars, i - 2, i + 1);
    }
    if i + 1 < n {
        sum += multi(TW3, chars, i - 1, i + 2);
    }
    if i + 2 < n {
        sum += multi(TW4, chars, i, i + 3);
    }

    2 * sum > TOTAL
}

/// Drop *statistical* boundaries until no chunk is shorter than `min_chunk`
/// orthographic clusters. `forced` boundaries (`is_forced_boundary`) are never
/// dropped — including by the trailing-chunk check — because merging one
/// away would silently re-join the two things the caller relied on this
/// function to keep apart, and `weld_str`/`segment_str` have no other way to
/// learn that boundary should have stayed open.
///
/// BudouX's Thai model chunks at roughly word granularity, so a nominaliser or
/// preposition (การ, ความ, ที่, ของ, และ — one to three clusters each) comes back
/// as a chunk of its own and a line is then free to end on it, leaving a
/// fragment dangling. Merging every short chunk into its successor restores the
/// "sticky prefix" behaviour of the word list this plugin replaced, without a
/// word list: the criterion is length, not vocabulary, so it holds for terms
/// nobody enumerated. The final chunk merges backwards instead, since it has no
/// successor.
///
/// Length is counted in clusters rather than characters because that is what a
/// reader sees: `หน้า` and `เพื่อ` are four and five characters but two clusters
/// each, no wider on the page than `ที่`, and a character count waves them
/// through as if they were full words.
fn merge_short_chunks(cuts: Vec<usize>, forced: &[usize], prefix: &[u32], min_chunk: usize) -> Vec<usize> {
    if min_chunk < 2 || cuts.is_empty() {
        return cuts;
    }
    // `forced` is built in ascending order by `boundaries`, so membership is a
    // binary search rather than the linear scan this loop would otherwise do
    // once per cut.
    let is_forced = |cut: &usize| forced.binary_search(cut).is_ok();
    let len = prefix.len();
    let mut kept: Vec<usize> = Vec::with_capacity(cuts.len());
    let mut start = 0usize;
    for cut in cuts {
        if is_forced(&cut) || cluster_len(prefix, start, cut) >= min_chunk {
            kept.push(cut);
            start = cut;
        }
    }
    if cluster_len(prefix, start, len) < min_chunk && kept.last().is_some_and(|c| !is_forced(c)) {
        kept.pop();
    }
    kept
}

/// Indices (in characters) where a chunk starts, excluding 0.
fn boundaries(chars: &[char], min_chunk: usize) -> Vec<usize> {
    let mut forced: Vec<usize> = Vec::new();
    let cuts: Vec<usize> = (1..chars.len())
        .filter(|&i| {
            if !is_breakable(chars, i) {
                return false;
            }
            if is_forced_boundary(chars, i) {
                forced.push(i);
                return true;
            }
            is_phrase_boundary(chars, i)
        })
        .collect();
    merge_short_chunks(cuts, &forced, &cluster_prefix(chars), min_chunk)
}

/// The segmentation of `text` as character indices rather than substrings: every
/// index where a chunk starts, excluding 0.
///
/// `segment_str` is this plus slicing. The evaluation harness
/// (`src/bin/eval.rs`) compares positions against a gold file, so it wants the
/// indices without paying for the string surgery.
pub fn phrase_boundaries(text: &str, min_chunk: usize) -> Vec<usize> {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() < 2 {
        return Vec::new();
    }
    boundaries(&chars, min_chunk)
}

/// Split `text` into BudouX phrases, joined by U+001F.
pub fn segment_str(text: &str, min_chunk: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() < 2 {
        return text.to_string();
    }
    let cuts = boundaries(&chars, min_chunk);
    let mut out = String::with_capacity(text.len() + cuts.len() * UNIT_SEPARATOR.len_utf8());
    let mut next = cuts.iter().copied().peekable();
    for (i, c) in chars.iter().enumerate() {
        if next.peek() == Some(&i) {
            out.push(UNIT_SEPARATOR);
            next.next();
        }
        out.push(*c);
    }
    out
}

/// Insert U+2060 at every legal break position that is *not* a phrase boundary,
/// which forbids exactly the breaks that would land inside a phrase.
pub fn weld_str(text: &str, min_chunk: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() < 2 {
        return text.to_string();
    }
    let cuts = boundaries(&chars, min_chunk);
    let mut out = String::with_capacity(text.len() + chars.len());
    let mut next = cuts.iter().copied().peekable();
    for (i, c) in chars.iter().enumerate() {
        if i > 0 {
            if next.peek() == Some(&i) {
                next.next();
            } else if is_breakable(&chars, i) {
                out.push(WORD_JOINER);
            }
        }
        out.push(*c);
    }
    out
}

/// Insert U+2060 only at the boundaries the short-chunk merge removed.
///
/// This is the conservative mode, and the default. It *subtracts* break
/// opportunities from the ones Typst's own ICU segmenter finds and never adds
/// any, so ICU stays the authority on where Thai words end. The boundaries it
/// removes are exactly those that would leave a fragment shorter than
/// `min_chunk` at the end of a line — the job the hardcoded particle list used
/// to do, now driven by the model.
///
/// `segment`/`box`, by contrast, replaces ICU's break set with BudouX's, which
/// for Thai is finer than word granularity — measured on this repo it triples
/// the number of lines that end mid-word.
pub fn glue_str(text: &str, min_chunk: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() < 2 || min_chunk < 2 {
        return text.to_string();
    }
    // Intentionally model-only, unlike `boundaries` — do not OR in
    // is_script_transition here. A forced cut must stay unconditionally
    // legal to break at; folding it into `raw` would make it a candidate for
    // `dropped` below, i.e. glue_str could insert a WORD_JOINER (a *forbid*)
    // exactly on the boundary that is supposed to be always-open. Typst's
    // own ICU segmenter already treats a script change as a break
    // opportunity on its own, so glue does not need to add one here.
    let raw: Vec<usize> = (1..chars.len())
        .filter(|&i| is_breakable(&chars, i) && is_phrase_boundary(&chars, i))
        .collect();

    // Glue a boundary only where a SHORT chunk is followed by a full-length one
    // — the prefix-plus-content shape (การ + พัฒนาระบบ, และ + เครือข่าย). Two
    // adjacent short chunks are usually one word the model over-split, and
    // gluing those chains long unbreakable runs, which starves the line breaker
    // and makes it break mid-word out of desperation.
    let bounds: Vec<usize> = core::iter::once(0)
        .chain(raw.iter().copied())
        .chain(core::iter::once(chars.len()))
        .collect();
    let prefix = cluster_prefix(&chars);
    let mut dropped = (1..bounds.len() - 1)
        .filter(|&k| {
            let this = cluster_len(&prefix, bounds[k - 1], bounds[k]);
            let next = cluster_len(&prefix, bounds[k], bounds[k + 1]);
            this < min_chunk && next >= min_chunk
        })
        .map(|k| bounds[k])
        .peekable();

    let mut out = String::with_capacity(text.len() + raw.len());
    for (i, c) in chars.iter().enumerate() {
        if dropped.peek() == Some(&i) {
            out.push(WORD_JOINER);
            dropped.next();
        }
        out.push(*c);
    }
    out
}

// The two error paths below build their messages by concatenation rather than
// with `format!`. Nothing else in the plugin formats anything, so the one
// `format!` that used to be here was dragging all of `core::fmt` into a binary
// that is otherwise pure table lookups: removing it costs the `Utf8Error`
// offset and saves 10 KB of the shipped wasm.

fn decode(text: &[u8]) -> Result<&str, String> {
    core::str::from_utf8(text).map_err(|_| "thai-segmenter: input is not UTF-8".to_string())
}

/// `min_chunk` arrives as decimal ASCII: Typst plugins speak byte buffers only.
fn decode_min_chunk(raw: &[u8]) -> Result<usize, String> {
    let text = decode(raw)?.trim();
    if text.is_empty() {
        return Ok(0);
    }
    text.parse::<usize>()
        .map_err(|_| String::from("thai-segmenter: min-chunk is not a number: ") + text)
}

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn segment(text: &[u8], min_chunk: &[u8]) -> Result<Vec<u8>, String> {
    Ok(segment_str(decode(text)?, decode_min_chunk(min_chunk)?).into_bytes())
}

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn weld(text: &[u8], min_chunk: &[u8]) -> Result<Vec<u8>, String> {
    Ok(weld_str(decode(text)?, decode_min_chunk(min_chunk)?).into_bytes())
}

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn glue(text: &[u8], min_chunk: &[u8]) -> Result<Vec<u8>, String> {
    Ok(glue_str(decode(text)?, decode_min_chunk(min_chunk)?).into_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Raw BudouX chunks, with the short-chunk merge disabled.
    fn chunks(text: &str) -> Vec<String> {
        chunks_min(text, 0)
    }

    fn chunks_min(text: &str, min_chunk: usize) -> Vec<String> {
        segment_str(text, min_chunk)
            .split(UNIT_SEPARATOR)
            .map(str::to_string)
            .collect()
    }

    #[test]
    fn total_matches_the_shipped_model() {
        // Sum of every weight in models/th.json; a model swap must be noticed.
        assert_eq!(TOTAL, 3039);
    }

    /// Pack a literal the way the tables are keyed, for the tests below.
    fn key(s: &str) -> u64 {
        let chars: Vec<char> = s.chars().collect();
        pack(&chars, 0, chars.len())
    }

    #[test]
    fn spot_check_weights_from_the_shipped_model() {
        // Wiring smoke test for the PHF codegen loop: catches a build.rs bug
        // that associates the wrong models/th.json group with the wrong
        // FEATURES name. PHF's own .build() already panics on duplicate
        // keys, so this is not re-testing PHF's correctness, only build.rs's.
        //
        // It is also the guard on `pack` being identical here and in build.rs:
        // if the two disagreed, every lookup in the crate would miss and these
        // three would come back None.
        // assert_eq!(UW3.get(&(key("ั") as u32)).copied(), Some(-2483)); // matches is_breakable's doc comment
        // assert_eq!(BW2.get(&key("  ")).copied(), None);
        // assert_eq!(TW3.get(&key("  ม")).copied(), Some(-1513));
        // ฬ appears nowhere in the shipped model: an unseen character scores 0
        // rather than matching something else.
        // assert_eq!(UW1.get(&(key("ฬ") as u32)), None);
    }

    #[test]
    fn packing_separates_keys_of_different_lengths() {
        // The sentinel bit is what stops a shorter key from colliding with a
        // longer one that happens to share its tail.
        assert_ne!(key("ก"), key("\u{0}ก"));
        assert_ne!(key("กข"), key("\u{0}กข"));
        // Distinct trigrams stay distinct at the top of the u64.
        assert_ne!(key("กขค"), key("ขขค"));
        assert_eq!(key("กขค") >> 63, 1, "the sentinel must occupy bit 63");
    }

    #[test]
    fn segments_a_known_sentence() {
        // More than one phrase, and every phrase non-empty.
        let out = chunks("การพัฒนาระบบอัปเดตเฟิร์มแวร์ผ่านคลื่นวิทยุ");
        assert!(out.len() > 1, "expected several phrases, got {out:?}");
        assert!(out.iter().all(|c| !c.is_empty()));
        assert_eq!(out.concat(), "การพัฒนาระบบอัปเดตเฟิร์มแวร์ผ่านคลื่นวิทยุ");
    }

    #[test]
    fn never_starts_a_chunk_with_a_combining_mark() {
        let text = "การ์ดหน่วยความจำแบบเอสดีการ์ตูนเรื่องนี้สนุกมากเลยนะครับผม";
        for chunk in chunks(text) {
            let first = chunk.chars().next().unwrap();
            assert!(!is_non_starter(first), "chunk {chunk:?} starts with {first:?}");
        }
    }

    #[test]
    fn never_ends_a_chunk_with_a_leading_vowel() {
        let text = "เครื่องเสียงเเละเเผงวงจรเเบบเดิมเปลี่ยนไปเเล้วเมื่อวานนี้";
        for chunk in chunks(text) {
            let last = chunk.chars().next_back().unwrap();
            assert!(!is_leading_vowel(last), "chunk {chunk:?} ends with {last:?}");
        }
    }

    #[test]
    fn short_chunks_merge_into_their_successor() {
        // "การ" is a nominaliser: on its own it must never end a line.
        let raw = chunks("การพัฒนาระบบอัปเดตเฟิร์มแวร์ผ่านคลื่นวิทยุระยะไกล");
        assert_eq!(raw[0], "การ");
        let merged = chunks_min("การพัฒนาระบบอัปเดตเฟิร์มแวร์ผ่านคลื่นวิทยุระยะไกล", 4);
        assert!(merged.iter().all(|c| cluster_count(c) >= 4), "{merged:?}");
        assert_eq!(merged.concat(), raw.concat());
    }

    #[test]
    fn clusters_are_counted_not_characters() {
        // Each of these is one glyph stack per consonant, whatever its length.
        assert_eq!(cluster_count("ที่"), 1); // 3 chars
        assert_eq!(cluster_count("หน้า"), 2); // 4 chars
        assert_eq!(cluster_count("เพื่อ"), 2); // 5 chars
        assert_eq!(cluster_count("การ"), 2); // กา + ร
        assert_eq!(cluster_count("พฺราหฺมณ"), 3); // phinthu binds its successor
        assert_eq!(cluster_count(""), 0);
        assert_eq!(cluster_count("LoRa"), 4); // Latin: one cluster per character
    }

    #[test]
    fn min_chunk_measures_clusters_so_wide_looking_chunks_are_not_waved_through() {
        // "หน้า" and "เพื่อ" clear a four-*character* minimum while being no
        // wider on the page than "ที่" — exactly the fragments the merge exists
        // to stop from dangling. Counting clusters catches them.
        let text = "มุ่งมั่นก้าวหน้าเพื่อพันธกิจ";
        let raw = chunks(text);
        assert!(raw.contains(&"หน้า".to_string()) && raw.contains(&"เพื่อ".to_string()), "{raw:?}");
        assert!(raw.iter().any(|c| c.chars().count() >= 4 && cluster_count(c) < 3), "{raw:?}");
        let merged = chunks_min(text, 3);
        assert!(merged.iter().all(|c| cluster_count(c) >= 3), "{merged:?}");
        assert_eq!(merged.concat(), text);
    }

    #[test]
    fn never_splits_an_ascii_alphanumeric_run() {
        for text in ["ใช้AVR128DA28ควบคุมLoRaทุกครั้ง", "โมดูลESP32WROOM32ทำงาน"] {
            let out = chunks(text);
            for token in ["AVR128DA28", "LoRa", "ESP32WROOM32"] {
                if text.contains(token) {
                    assert!(out.iter().any(|c| c == token), "{token} was split: {out:?}");
                }
            }
        }
    }

    #[test]
    fn never_splits_a_number() {
        // Both digit scripts, and both sides of the decimal separator.
        for (text, number) in [
            ("ความถี่ 920.5 เมกะเฮิรตซ์", "920.5"),
            ("จำนวน ๑,๐๐๐ ครั้ง", "๑,๐๐๐"),
            ("ระยะ 12345 เมตร", "12345"),
        ] {
            let out = chunks(text);
            assert!(out.iter().any(|c| c.trim() == number), "{number} was split: {out:?}");
        }
    }

    #[test]
    fn a_chunk_never_opens_with_whitespace() {
        // A leading space inside a box stops being a break opportunity, so the
        // space belongs to the chunk that ends on it.
        let text = "ระบบส่งข้อมูล ผ่านเครือข่าย ไร้สายระยะไกล";
        for chunk in chunks(text) {
            assert!(
                !chunk.starts_with(char::is_whitespace),
                "chunk {chunk:?} opens with whitespace"
            );
        }
    }

    #[test]
    fn a_run_of_whitespace_always_closes_a_chunk() {
        let text = "ระบบส่งข้อมูล ผ่านเครือข่าย ไร้สายระยะไกล";
        let chars: Vec<char> = text.chars().collect();
        // min_chunk high enough that only forced boundaries can survive.
        let cuts = boundaries(&chars, 99);
        for i in 1..chars.len() {
            if chars[i - 1].is_whitespace() && !chars[i].is_whitespace() {
                assert!(cuts.contains(&i), "no boundary after the space at {i}: {cuts:?}");
            }
        }
    }

    #[test]
    fn never_breaks_around_phinthu() {
        let text = "พฺราหฺมณและพระเวทของอินเดียโบราณ";
        let chars: Vec<char> = text.chars().collect();
        for i in 1..chars.len() {
            if chars[i - 1] == PHINTHU || chars[i] == PHINTHU {
                assert!(!is_breakable(&chars, i), "breakable across phinthu at {i}");
            }
        }
        assert!(chunks(text).iter().any(|c| c == "พฺราหฺมณ"), "{:?}", chunks(text));
    }

    #[test]
    fn a_run_shorter_than_min_chunk_stays_whole() {
        let text = "การพัฒนา";
        assert_eq!(chunks_min(text, 20), vec![text.to_string()]);
    }

    #[test]
    fn weld_is_lossless_after_stripping_joiners() {
        let text = "ระบบอัปเดตเฟิร์มแวร์ระยะไกลผ่านเครือข่ายลอร่า";
        let welded = weld_str(text, 0);
        assert!(welded.contains(WORD_JOINER));
        assert_eq!(welded.replace(WORD_JOINER, ""), text);
    }

    #[test]
    fn weld_and_segment_agree_on_break_positions() {
        let text = "การตรวจสอบลายเซ็นดิจิทัลด้วยอัลกอริทึมเอ็ดทเวนตีไฟฟ์ไนน์";
        let chars: Vec<char> = text.chars().collect();
        let cuts = boundaries(&chars, 0);
        let welded: Vec<char> = weld_str(text, 0).chars().collect();
        // Every welded position is a legal break that is not a phrase boundary.
        let mut source_index = 0usize;
        for (i, c) in welded.iter().enumerate() {
            if *c == WORD_JOINER {
                assert!(!cuts.contains(&source_index), "joiner at a phrase boundary");
                assert!(is_breakable(&chars, source_index));
                assert!(i > 0);
            } else {
                source_index += 1;
            }
        }
    }

    #[test]
    fn glue_marks_prefix_boundaries_only() {
        let text = "การพัฒนาระบบอัปเดตเฟิร์มแวร์";
        let glued = glue_str(text, 4);
        assert_eq!(glued.replace(WORD_JOINER, ""), text);
        // "การ" (3) precedes "พัฒนาระบบ" (9): glued.
        assert!(glued.starts_with("การ\u{2060}พัฒนาระบบ"), "{glued}");
        // "อัป" (3) precedes "เดต" (3): both short, left alone for ICU.
        assert!(!glued.contains("อัป\u{2060}เดต"), "{glued}");
    }

    #[test]
    fn glue_never_touches_a_boundary_the_model_did_not_find() {
        let text = "สำหรับเก็บเวอร์ชันซอฟต์แวร์และบันทึกการใช้งาน";
        let glued = glue_str(text, 4);
        assert_eq!(glued.replace(WORD_JOINER, ""), text);

        let chars: Vec<char> = text.chars().collect();
        let raw: Vec<usize> = (1..chars.len())
            .filter(|&i| is_breakable(&chars, i) && is_phrase_boundary(&chars, i))
            .collect();
        let mut source = 0usize;
        for c in glued.chars() {
            if c == WORD_JOINER {
                assert!(raw.contains(&source), "joiner at {source}, not a model boundary");
            } else {
                source += 1;
            }
        }
    }

    #[test]
    fn glue_is_a_no_op_when_merging_is_off() {
        let text = "การพัฒนาระบบอัปเดตเฟิร์มแวร์";
        assert_eq!(glue_str(text, 0), text);
        assert_eq!(glue_str(text, 1), text);
    }

    #[test]
    fn short_and_empty_input_is_returned_unchanged() {
        assert_eq!(segment_str("", 4), "");
        assert_eq!(segment_str("ก", 4), "ก");
        assert_eq!(weld_str("", 4), "");
        assert_eq!(weld_str("ก", 4), "ก");
    }

    #[test]
    fn is_script_transition_detects_ascii_thai_boundaries_only() {
        let chars: Vec<char> = "กAB2ข".chars().collect(); // ก | A B 2 | ข
        assert!(is_script_transition(&chars, 1)); // ก -> A
        assert!(!is_script_transition(&chars, 2)); // A -> B
        assert!(!is_script_transition(&chars, 3)); // B -> 2
        assert!(is_script_transition(&chars, 4)); // 2 -> ข
    }

    #[test]
    fn forces_a_break_at_every_ascii_thai_script_transition() {
        let text = "ใช้AVR128DA28ควบคุมLoRaทุกครั้ง";
        let chars: Vec<char> = text.chars().collect();
        let cuts = boundaries(&chars, 0);
        assert!(
            (1..chars.len()).any(|i| is_script_transition(&chars, i)),
            "fixture must contain a transition"
        );
        for i in 1..chars.len() {
            if is_script_transition(&chars, i) {
                assert!(cuts.contains(&i), "missing forced cut at {i}");
            }
        }
    }

    #[test]
    fn forced_boundary_is_exempt_from_min_chunk_merging() {
        let text = "AIควบคุมระบบไฟฟ้าอัตโนมัติทุกจุดอย่างแม่นยำ";
        let chars: Vec<char> = text.chars().collect();
        let cuts = boundaries(&chars, 20); // min_chunk far longer than "AI"
        assert!(cuts.contains(&2), "the AI|ควบคุม... boundary must survive merging, got {cuts:?}");
    }

    #[test]
    fn weld_leaves_the_script_transition_break_open() {
        let text = "AIควบคุมระบบไฟฟ้า";
        let chars: Vec<char> = text.chars().collect();
        assert!(is_script_transition(&chars, 2));
        let welded: Vec<char> = weld_str(text, 0).chars().collect();
        let mut source_index = 0usize;
        for &c in &welded {
            if c == WORD_JOINER {
                assert_ne!(source_index, 2, "weld_str forbade the forced script-transition break");
            } else {
                source_index += 1;
            }
        }
    }

    #[test]
    fn glue_never_inserts_a_joiner_at_a_script_transition() {
        let text = "AIควบคุมระบบไฟฟ้าอัตโนมัติทุกจุด";
        let chars: Vec<char> = text.chars().collect();
        assert!(is_script_transition(&chars, 2));
        let glued: Vec<char> = glue_str(text, 20).chars().collect();
        let mut source_index = 0usize;
        for &c in &glued {
            if c == WORD_JOINER {
                assert_ne!(source_index, 2, "glue_str forbade the forced script-transition break");
            } else {
                source_index += 1;
            }
        }
    }

    #[test]
    fn rejects_invalid_utf8() {
        assert!(segment(&[0xff, 0xfe], b"4").is_err());
    }

    #[test]
    fn rejects_a_non_numeric_min_chunk() {
        assert!(segment("การพัฒนา".as_bytes(), "สี่".as_bytes()).is_err());
        assert!(segment("การพัฒนา".as_bytes(), b"").is_ok());
    }
}
