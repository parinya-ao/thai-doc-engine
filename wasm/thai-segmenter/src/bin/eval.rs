// Host-only measurement harness for the segmenter. Behind the `cli` feature so
// the wasm build never sees it:
//
//     cargo run --release --features cli --bin eval -- <mode> <file> [min-chunk]
//
// Modes:
//   dump   one line per input line, chunks separated by U+2581 — the format
//          `score` consumes, so a dump can be hand-corrected into a gold file.
//   score  precision / recall / F1 of the predicted boundaries against a gold
//          file marked up with U+2581. Boundaries, not chunks, are the unit:
//          a chunk is only right if both its ends are, which double-counts
//          every error and makes the score look worse than it is.
//   stats  chunk-length distribution, in characters and in orthographic
//          clusters. The two disagree (a cluster is one to four characters),
//          which is why `min_chunk` counts clusters.
//   bench  characters segmented per second. Hand-rolled rather than criterion:
//          the plugin's whole selling point is that it has almost no
//          dependencies, and the changes worth measuring here are large enough
//          that a wall clock resolves them.

use std::{
    collections::BTreeMap,
    env, fs,
    hint::black_box,
    process,
    time::{Duration, Instant},
};

use thai_segmenter::{cluster_count, phrase_boundaries, segment_str};

/// U+2581 LOWER ONE EIGHTH BLOCK — BudouX's own delimiter in training data.
const DELIM: char = '\u{2581}';

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let (mode, path) = match args.as_slice() {
        [mode, path, ..] => (mode.as_str(), path.as_str()),
        _ => {
            eprintln!("usage: eval <dump|score|stats|bench> <file> [min-chunk]");
            process::exit(2);
        }
    };
    let min_chunk: usize = args.get(2).map_or(3, |a| a.parse().expect("min-chunk must be a number"));

    let text = fs::read_to_string(path).unwrap_or_else(|e| panic!("cannot read {path}: {e}"));
    let lines: Vec<&str> = text.lines().filter(|l| !l.trim().is_empty()).collect();

    match mode {
        "dump" => dump(&lines, min_chunk),
        "score" => score(&lines, min_chunk),
        "stats" => stats(&lines, min_chunk),
        "bench" => bench(&lines, min_chunk),
        other => {
            eprintln!("unknown mode {other:?}");
            process::exit(2);
        }
    }
}

fn dump(lines: &[&str], min_chunk: usize) {
    for line in lines {
        let cuts = phrase_boundaries(line, min_chunk);
        let mut next = cuts.iter().copied().peekable();
        let mut out = String::with_capacity(line.len() + cuts.len() * DELIM.len_utf8());
        for (i, c) in line.chars().enumerate() {
            if next.peek() == Some(&i) {
                out.push(DELIM);
                next.next();
            }
            out.push(c);
        }
        println!("{out}");
    }
}

/// Strip the delimiters from a gold line, returning the plain text and the
/// character indices the delimiters stood at.
fn split_gold(line: &str) -> (String, Vec<usize>) {
    let mut plain = String::with_capacity(line.len());
    let mut cuts = Vec::new();
    for c in line.chars() {
        if c == DELIM {
            // A leading delimiter marks the start of the line, which is not a
            // boundary anyone predicts; `phrase_boundaries` excludes index 0.
            if !plain.is_empty() {
                cuts.push(plain.chars().count());
            }
        } else {
            plain.push(c);
        }
    }
    (plain, cuts)
}

fn score(lines: &[&str], min_chunk: usize) {
    let (mut hit, mut predicted, mut gold_total) = (0usize, 0usize, 0usize);
    for line in lines {
        let (plain, gold) = split_gold(line);
        let pred = phrase_boundaries(&plain, min_chunk);
        // Both lists are ascending and duplicate-free, so a merge counts the
        // intersection without allocating a set.
        let (mut i, mut j) = (0usize, 0usize);
        while i < pred.len() && j < gold.len() {
            match pred[i].cmp(&gold[j]) {
                std::cmp::Ordering::Equal => {
                    hit += 1;
                    i += 1;
                    j += 1;
                }
                std::cmp::Ordering::Less => i += 1,
                std::cmp::Ordering::Greater => j += 1,
            }
        }
        predicted += pred.len();
        gold_total += gold.len();
    }

    let ratio = |num: usize, den: usize| if den == 0 { 0.0 } else { num as f64 / den as f64 };
    let (p, r) = (ratio(hit, predicted), ratio(hit, gold_total));
    let f1 = if p + r == 0.0 { 0.0 } else { 2.0 * p * r / (p + r) };
    println!("lines      {}", lines.len());
    println!("gold       {gold_total}");
    println!("predicted  {predicted}");
    println!("correct    {hit}");
    println!("precision  {p:.4}");
    println!("recall     {r:.4}");
    println!("f1         {f1:.4}");
}

fn bench(lines: &[&str], min_chunk: usize) {
    let chars: usize = lines.iter().map(|l| l.chars().count()).sum();
    // Warm the caches, then run for a fixed wall time rather than a fixed
    // iteration count so the corpus size does not decide the sample size.
    for line in lines {
        black_box(segment_str(line, min_chunk));
    }
    let budget = Duration::from_secs(2);
    let start = Instant::now();
    let mut rounds = 0u64;
    while start.elapsed() < budget {
        for line in lines {
            black_box(segment_str(line, min_chunk));
        }
        rounds += 1;
    }
    let elapsed = start.elapsed().as_secs_f64();
    let total = rounds as f64 * chars as f64;
    println!("corpus     {chars} chars in {} lines", lines.len());
    println!("rounds     {rounds} in {elapsed:.2}s");
    println!("throughput {:.2} Mchar/s", total / elapsed / 1e6);
    println!("per round  {:.3} ms", 1e3 * elapsed / rounds as f64);
}

fn stats(lines: &[&str], min_chunk: usize) {
    let mut by_char: BTreeMap<usize, usize> = BTreeMap::new();
    let mut by_cluster: BTreeMap<usize, usize> = BTreeMap::new();
    let mut total = 0usize;
    for line in lines {
        let chars: Vec<char> = line.chars().collect();
        let cuts = phrase_boundaries(line, min_chunk);
        let mut start = 0usize;
        for end in cuts.iter().copied().chain(std::iter::once(chars.len())) {
            let chunk: String = chars[start..end].iter().collect();
            *by_char.entry(end - start).or_default() += 1;
            *by_cluster.entry(cluster_count(&chunk)).or_default() += 1;
            total += 1;
            start = end;
        }
    }
    println!("chunks {total} (min-chunk {min_chunk})");
    let show = |label: &str, hist: &BTreeMap<usize, usize>| {
        println!("{label}:");
        for (len, n) in hist {
            println!("  {len:>3} {n:>6} {:>6.2}%", 100.0 * *n as f64 / total as f64);
        }
    };
    show("characters per chunk", &by_char);
    show("clusters per chunk", &by_cluster);
}
