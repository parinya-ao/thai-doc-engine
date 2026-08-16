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

/// Characters that must never end a chunk: the leading vowels เ แ โ ใ ไ, which
/// are written before the consonant they are pronounced after.
fn is_leading_vowel(c: char) -> bool {
    matches!(c, '\u{0E40}'..='\u{0E44}')
}

/// Whether a break at `i` is *structurally* legal, independent of the model.
///
/// The trained weights already score these positions strongly negative
/// (`UW3["ั"] = -3075`), so this rarely changes an answer — it turns a
/// statistical property into a guaranteed one.
fn is_breakable(chars: &[char], i: usize) -> bool {
    i > 0 && i < chars.len() && !is_non_starter(chars[i]) && !is_leading_vowel(chars[i - 1])
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

fn lookup(table: &phf::Map<&'static str, i32>, key: &str) -> i64 {
    table.get(key).copied().unwrap_or(0) as i64
}

/// Score of the n-gram `chars[start..end]` in `table`, reusing `buf` so the hot
/// loop does not allocate for every one of the thirteen feature lookups.
fn score_ngram(table: &phf::Map<&'static str, i32>, chars: &[char], start: usize, end: usize, buf: &mut String) -> i64 {
    buf.clear();
    buf.extend(chars[start..end].iter());
    lookup(table, buf)
}

/// BudouX's decision for the boundary before `chars[i]`, with `i > 0`.
///
/// Reference: `sum(weights) - 0.5 * TOTAL > 0`, rewritten as `2 * sum > TOTAL`.
fn is_phrase_boundary(chars: &[char], i: usize, buf: &mut String) -> bool {
    let n = chars.len();
    let mut sum: i64 = 0;

    if i > 2 {
        sum += score_ngram(UW1, chars, i - 3, i - 2, buf);
    }
    if i > 1 {
        sum += score_ngram(UW2, chars, i - 2, i - 1, buf);
    }
    sum += score_ngram(UW3, chars, i - 1, i, buf);
    sum += score_ngram(UW4, chars, i, i + 1, buf);
    if i + 1 < n {
        sum += score_ngram(UW5, chars, i + 1, i + 2, buf);
    }
    if i + 2 < n {
        sum += score_ngram(UW6, chars, i + 2, i + 3, buf);
    }

    if i > 1 {
        sum += score_ngram(BW1, chars, i - 2, i, buf);
    }
    sum += score_ngram(BW2, chars, i - 1, i + 1, buf);
    if i + 1 < n {
        sum += score_ngram(BW3, chars, i, i + 2, buf);
    }

    if i > 2 {
        sum += score_ngram(TW1, chars, i - 3, i, buf);
    }
    if i > 1 {
        sum += score_ngram(TW2, chars, i - 2, i + 1, buf);
    }
    if i + 1 < n {
        sum += score_ngram(TW3, chars, i - 1, i + 2, buf);
    }
    if i + 2 < n {
        sum += score_ngram(TW4, chars, i, i + 3, buf);
    }

    2 * sum > TOTAL
}

/// Drop *statistical* boundaries until no chunk is shorter than `min_chunk`
/// characters. `forced` boundaries (`is_script_transition`) are never
/// dropped — including by the trailing-chunk check — because merging one
/// away would silently re-join the two scripts the caller relied on this
/// function to keep apart, and `weld_str`/`segment_str` have no other way to
/// learn that boundary should have stayed open.
///
/// BudouX's Thai model chunks at roughly word granularity, so a nominaliser or
/// preposition (การ, ความ, ที่, ของ, และ — all three to four characters) comes
/// back as a chunk of its own and a line is then free to end on it, leaving a
/// fragment dangling. Merging every short chunk into its successor restores the
/// "sticky prefix" behaviour of the word list this plugin replaced, without a
/// word list: the criterion is length, not vocabulary, so it holds for terms
/// nobody enumerated. The final chunk merges backwards instead, since it has no
/// successor.
fn merge_short_chunks(cuts: Vec<usize>, forced: &[usize], len: usize, min_chunk: usize) -> Vec<usize> {
    if min_chunk < 2 || cuts.is_empty() {
        return cuts;
    }
    let mut kept: Vec<usize> = Vec::with_capacity(cuts.len());
    let mut start = 0usize;
    for cut in cuts {
        if forced.contains(&cut) || cut - start >= min_chunk {
            kept.push(cut);
            start = cut;
        }
    }
    if len - start < min_chunk && kept.last().is_some_and(|c| !forced.contains(c)) {
        kept.pop();
    }
    kept
}

/// Indices (in characters) where a chunk starts, excluding 0.
fn boundaries(chars: &[char], min_chunk: usize) -> Vec<usize> {
    let mut buf = String::with_capacity(16);
    let mut forced: Vec<usize> = Vec::new();
    let cuts: Vec<usize> = (1..chars.len())
        .filter(|&i| {
            if !is_breakable(chars, i) {
                return false;
            }
            if is_script_transition(chars, i) {
                forced.push(i);
                return true;
            }
            is_phrase_boundary(chars, i, &mut buf)
        })
        .collect();
    merge_short_chunks(cuts, &forced, chars.len(), min_chunk)
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
    let mut buf = String::with_capacity(16);
    let raw: Vec<usize> = (1..chars.len())
        .filter(|&i| is_breakable(&chars, i) && is_phrase_boundary(&chars, i, &mut buf))
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
    let mut dropped = (1..bounds.len() - 1)
        .filter(|&k| {
            let this = bounds[k] - bounds[k - 1];
            let next = bounds[k + 1] - bounds[k];
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

fn decode(text: &[u8]) -> Result<&str, String> {
    core::str::from_utf8(text).map_err(|e| format!("thai-segmenter: input is not UTF-8: {e}"))
}

/// `min_chunk` arrives as decimal ASCII: Typst plugins speak byte buffers only.
fn decode_min_chunk(raw: &[u8]) -> Result<usize, String> {
    let text = decode(raw)?.trim();
    if text.is_empty() {
        return Ok(0);
    }
    text.parse::<usize>()
        .map_err(|_| format!("thai-segmenter: min-chunk is not a number: {text:?}"))
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
        assert_eq!(TOTAL, 4401);
    }

    #[test]
    fn spot_check_weights_from_the_shipped_model() {
        // Wiring smoke test for the PHF codegen loop: catches a build.rs bug
        // that associates the wrong models/th.json group with the wrong
        // FEATURES name. PHF's own .build() already panics on duplicate
        // keys, so this is not re-testing PHF's correctness, only build.rs's.
        assert_eq!(UW3.get("ั").copied(), Some(-3075)); // matches is_breakable's doc comment
        assert_eq!(BW2.get("  ").copied(), Some(-3208));
        assert_eq!(TW3.get("  ม").copied(), Some(-1513));
        assert_eq!(UW1.get("ไม่มีทางเจอ"), None);
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
        assert!(merged.iter().all(|c| c.chars().count() >= 4), "{merged:?}");
        assert_eq!(merged.concat(), raw.concat());
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
        let mut buf = String::new();
        let raw: Vec<usize> = (1..chars.len())
            .filter(|&i| is_breakable(&chars, i) && is_phrase_boundary(&chars, i, &mut buf))
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
