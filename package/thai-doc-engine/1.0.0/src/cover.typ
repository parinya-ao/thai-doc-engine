// cover.typ — Layer 2: annual-report style cover page
//
// Implements the "Corporate Clean" annual-report cover system described in docs/cover.md:
// five functional zones, Van de Graaf ninths page geometry, a 12-column Swiss grid, optical-
// centre placement, 60-30-10 colour with WCAG-checkable contrast, and phrase-safe Thai
// display typesetting.

#import "config.typ": load-typography, thai-chunks, thai-never
#import "metrics.typ": thai-leading, cover-margins, thai-merge-keeps, thai-numerals, cover-hero-heights

#let cover(
  brand: none, // Zone 1 — brand lockup, sits on the top margin
  title: none, // Zone 2 — document classification title (Thai)
  title-en: none, // Zone 2 — Latin counterpart
  subtitle: none, // Zone 2 — supporting line
  period: none, // Zone 3 — fiscal year / planning horizon
  meta: (), // Zone 5 — array of regulatory metadata items
  hero: auto, // Zone 4 — auto = generated geometry, none = empty, or any content
  palette: (:), // (base:, brand:, signal:) — 60 / 30 / 10
  sizes: (:), // pt overrides, pre-scaling
  canon: "van-de-graaf",
  optical: 0.45, // title centre as a fraction of page height (0.382 = golden alternative)
  columns: 12,
  gutter: auto, // auto -> 4mm scaled; 12 cols at 4mm gives exactly 8mm columns on A4
  font: "TH Sarabun New",
  numerals: "arabic", // "arabic" | "thai"
  k-display: 1.35, // leading factor for the display title
  k-body: 1.55, // leading factor for everything else
  tracking: -0.01em,
  fit: true, // shrink the display type until the title stack fits its budget
  min-hero: auto, // floor on the hero band before the title is allowed to shrink into it
  grid-debug: false,
  counter-reset: true,
  phrase-break: true,
  phrase-min-run: auto, // auto -> typography.json
  phrase-min-chunk: auto, // auto -> typography.json
  phrase-keep: auto, // auto -> typography.json keep-phrases
  typography: none, // dict or path, as per thai-document-engine
  orphan-guard: true,
) = {
  // Same data-driven config the engine uses. The keep-phrase layer matters more here than in
  // body text: BudouX's Thai model segments at morpheme level, so at the default min-chunk it
  // cuts "ยั่งยืน" into ยั่ง|ยืน and "ดำเนินงาน" into ดำเนิน|งาน. In a paragraph those rarely land
  // on a line end; in a two-line display title they very often do.
  let th-config = load-typography(typography)
  let phrase-min-run = if phrase-min-run == auto {
    th-config.at("phrase-min-run", default: 8)
  } else { phrase-min-run }
  let phrase-min-chunk = if phrase-min-chunk == auto {
    th-config.at("phrase-min-chunk", default: 3)
  } else { phrase-min-chunk }
  let phrase-keep = if phrase-keep == auto {
    th-config.at("keep-phrases", default: ())
  } else { phrase-keep }

  let pal = (
    // Defaults clear WCAG AAA on the base: brand 16.88:1, signal 9.45:1.
    base: rgb("#FFFFFF"),
    brand: rgb("#0F1D33"),
    signal: rgb("#8C1220"),
  ) + palette

  // Latin-calibrated sizes from docs/cover.md multiplied through optical-scale and rounded:
  // display 36-54pt -> 55-83pt, subtitle 16-24pt -> 24-37pt, metadata 9-11pt -> 14-17pt.
  let sz = (
    brand: 15pt,
    title: 64pt,
    title-en: 26pt,
    subtitle: 24pt,
    period: 64pt,
    meta: 14pt,
  ) + sizes

  assert(
    numerals in ("arabic", "thai"),
    message: "numerals must be \"arabic\" or \"thai\" — got " + repr(numerals),
  )

  // margin: 0pt makes place() coordinates absolute page coordinates; header/footer/numbering
  // are cleared so a cover placed inside thai-document-engine does not inherit page furniture.
  // `paper` is deliberately NOT set — the one-off page inherits it from the enclosing
  // `set page`, which is what lets the same call render on a4, a5, a3 or us-letter.
  page(
    margin: 0pt,
    header: none,
    footer: none,
    numbering: none,
    fill: pal.base,
    {
      // These MUST be issued before the `context` below, not inside it. A context expression
      // resolves styles at its own position, so set rules written after it opens are invisible
      // to the measure() calls within — which silently mis-measures the title stack (wrong
      // font, and top-edge defaulting to "cap-height" instead of "ascender") and drops the
      // period zone on top of the last title line.
      set text(
        font: font,
        lang: "th",
        region: "th",
        fill: pal.brand,
        // The measured ink fit — see sarabun-metrics.
        top-edge: "ascender",
        bottom-edge: "descender",
      )
      // Thai display type is never justified (docs/cover.md, Multi-Line Step 3): with no
      // native word spaces, stretching a line opens ragged gaps between phrases instead.
      set par(justify: false, leading: thai-leading(k-body))

      // layout(), not page.width/page.height: on a `flipped` page those two still report the
      // unflipped 210x297, so a landscape cover would be laid out to portrait dimensions and
      // run off the sheet. With margin: 0pt the layout container is exactly the page box.
      layout(size => {
        let (w, h) = (size.width, size.height)
        // Scale against A4 on whichever axis binds first. For the A series this is exact either
        // way (aspect is preserved: A5 -> 0.707, A3 -> 1.414), and it is the only form that
        // survives a non-ISO aspect ratio. Width alone would set landscape A4 at 1.414x on a
        // 210mm-tall page; the geometric mean is no better there, because flipping a sheet
        // leaves its area — and therefore sqrt(area) — completely unchanged. Taking the minimum
        // costs about 4% on us-letter (0.939 vs 0.983) and cannot overflow on any paper.
        let s = calc.min(w / 210mm, h / 297mm)
        let m = cover-margins(w, h, canon)
        let text-w = w - m.left - m.right
        let g = if gutter == auto { 4mm * s } else { gutter }
        let col-w = (text-w - (columns - 1) * g) / columns
        let min-hero = if min-hero == auto { 22mm * s } else { min-hero }

        // Phrase-safe Thai breaking, reusing the BudouX plugin wrappers above. This is
        // docs/cover.md's four-step multi-line recipe: thai-chunks() is the morphological
        // parse (Step 1), box() per phrase is the break-control marker (Step 2, and the
        // equivalent of word-break: keep-all in Step 3), and merging the final two phrases is
        // the orphan guard.
        let phrased(body) = {
          show regex(if phrase-break {
            "\\p{sc=Thai}{" + str(phrase-min-run) + ",}"
          } else { thai-never }): it => {
            let phrases = thai-merge-keeps(
              thai-chunks(it.text, phrase-min-chunk),
              phrase-keep,
            )
            if phrases.len() <= 1 {
              it
            } else if orphan-guard and phrases.len() >= 3 {
              let head = phrases.slice(0, -2).map(box)
              (head + (box(phrases.at(-2) + phrases.at(-1)),)).join()
            } else {
              phrases.map(box).join()
            }
          }
          body
        }

        let line-at(y, stroke-w, colour) = place(
          top + left,
          dx: m.left,
          dy: y,
          line(length: text-w, stroke: stroke-w + colour),
        )

        // Vertical rhythm between zones, scaled with the paper.
        let gap = 5mm * s

        // --- Zone 1: brand lockup --------------------------------------------------------
        let brand-block = if brand == none { none } else {
          block(width: text-w, {
            set text(size: sz.brand * s, weight: "bold", tracking: 0.1em)
            phrased(brand)
          })
        }
        let brand-h = if brand-block == none { 0pt } else {
          measure(block(width: text-w, brand-block)).height
        }

        // --- Zone 5: regulatory metadata, sitting on the bottom margin line --------------
        let meta-block = if meta.len() == 0 { none } else {
          block(width: text-w, {
            set text(size: sz.meta * s, fill: pal.brand.lighten(20%))
            grid(
              columns: (1fr,) * meta.len(),
              column-gutter: g,
              align: left,
              ..meta.map(item => phrased(item)),
            )
          })
        }
        let meta-h = if meta-block == none { 0pt } else {
          measure(block(width: text-w, meta-block)).height
        }
        let meta-y = h - m.bottom - meta-h

        // --- Zone 3: temporal periodisation ---------------------------------------------
        // Thai digits draw ~5% shorter than Latin ones in this font (๒๕๖๘ tops out at 0.460em
        // vs 0.484em for 2568), so they get a small compensating bump.
        let period-block = if period == none { none } else {
          let body = if numerals == "thai" and type(period) in (int, str) {
            thai-numerals(period)
          } else { period }
          block(width: text-w, {
            set text(
              size: sz.period * s * (if numerals == "thai" { 1.06 } else { 1.0 }),
              weight: "bold",
              fill: pal.signal,
              tracking: tracking,
            )
            body
          })
        }
        let period-h = if period-block == none { 0pt } else {
          measure(block(width: text-w, period-block)).height
        }

        // --- Zone 2: classification title, optically centred ------------------------------
        // Built at a shrink factor so the display size can be fitted to the space actually
        // available. All three lines shrink together, preserving the size hierarchy.
        let make-title(f) = {
          if title != none {
            block(width: text-w, {
              set par(leading: thai-leading(k-display))
              set text(size: sz.title * s * f, weight: "bold", tracking: tracking)
              phrased(title)
            })
          }
          if title-en != none {
            block(width: text-w, above: 0.55em, {
              set text(size: sz.title-en * s * f, lang: "en", tracking: 0em)
              title-en
            })
          }
          if subtitle != none {
            block(width: text-w, above: 0.9em, {
              set text(size: sz.subtitle * s * f, fill: pal.brand.lighten(25%))
              phrased(subtitle)
            })
          }
        }

        // The title is centred on the optical anchor, so it grows symmetrically about it and
        // eats twice the distance to whichever neighbour it reaches first: the brand lockup
        // above, or the period + hero + metadata below. A long Thai title at the default 64pt
        // runs to three or four lines and would otherwise crush the hero band out of existence.
        // calc.max keeps the budget positive on very short or landscape pages, where the zones
        // below the anchor can already consume everything. A non-positive budget would otherwise
        // skip the fit loop entirely and let the title overrun the page — the opposite of what
        // a cramped page needs.
        let title-budget = calc.max(
          2
            * calc.min(
              // 3.5 gaps, not 2: the band below the title loses one gap before the period,
              // one after it, and the 1.5 that hero-bottom holds back off the metadata rule.
              // Counting only the first two silently ate into min-hero.
              meta-y - optical * h - period-h - 3.5 * gap - min-hero,
              optical * h - m.top - brand-h - gap,
            ),
          12mm * s,
        )
        let fit-factor = 1.0
        let title-stack = make-title(fit-factor)
        let title-h = measure(block(width: text-w, title-stack)).height
        if fit {
          // Step down until it fits. Bounded: 0.04 per step from 1.0 to the 0.45 floor.
          while title-h > title-budget and fit-factor > 0.45 {
            fit-factor = fit-factor - 0.04
            title-stack = make-title(fit-factor)
            title-h = measure(block(width: text-w, title-stack)).height
          }
        }
        let title-y = optical * h - title-h / 2
        let period-y = title-y + title-h + gap

        if brand-block != none {
          place(top + left, dx: m.left, dy: m.top, brand-block)
        }

        place(top + left, dx: m.left, dy: title-y, block(width: text-w, title-stack))
        if period-block != none {
          place(top + left, dx: m.left, dy: period-y, block(width: text-w, period-block))
        }

        // --- Zone 4: hero abstraction ----------------------------------------------------
        let hero-top = period-y + period-h + gap
        let hero-bottom = meta-y - 1.5 * gap
        let hero-h = hero-bottom - hero-top
        if hero != none and hero-h > 0.5 * min-hero {
          place(top + left, dx: m.left, dy: hero-top, block(width: text-w, height: hero-h, {
            if hero == auto {
              // The Van de Graaf construction lines that generated the page, drawn as
              // near-invisible hairlines, plus a column-aligned bar field reading as a data
              // abstraction. Both land on the same 12-column module as the type above.
              let faint = pal.brand.transparentize(90%)
              place(top + left, line(
                start: (0pt, 0pt),
                end: (text-w, hero-h),
                stroke: 0.3pt + faint,
              ))
              place(top + left, line(
                start: (text-w, 0pt),
                end: (0pt, hero-h),
                stroke: 0.3pt + faint,
              ))
              place(top + left, line(
                start: (0pt, 0pt),
                end: (text-w / 2, hero-h),
                stroke: 0.3pt + faint,
              ))
              place(top + left, line(
                start: (text-w, 0pt),
                end: (text-w / 2, hero-h),
                stroke: 0.3pt + faint,
              ))
              for i in range(columns) {
                let bar-h = cover-hero-heights.at(calc.rem(i, cover-hero-heights.len())) * hero-h
                let fill-colour = if calc.rem(i, 6) == 5 {
                  pal.signal
                } else {
                  pal.brand.transparentize(45% + calc.rem(i * 13, 40) * 1%)
                }
                place(
                  top + left,
                  dx: i * (col-w + g),
                  dy: hero-h - bar-h,
                  rect(width: col-w, height: bar-h, fill: fill-colour, stroke: none),
                )
              }
            } else {
              hero
            }
          }))
        }

        if meta-block != none {
          line-at(meta-y - 0.7em.to-absolute() * s, 0.5pt, pal.brand.transparentize(65%))
          place(top + left, dx: m.left, dy: meta-y, block(width: text-w, meta-block))
        }

        // --- Grid overlay ------------------------------------------------------------------
        if grid-debug {
          let dbg = rgb("#E5006D")
          place(top + left, dx: m.left, dy: m.top, rect(
            width: text-w,
            height: h - m.top - m.bottom,
            stroke: 0.4pt + dbg.transparentize(40%),
          ))
          for i in range(columns) {
            place(top + left, dx: m.left + i * (col-w + g), dy: m.top, rect(
              width: col-w,
              height: h - m.top - m.bottom,
              fill: dbg.transparentize(92%),
              stroke: none,
            ))
          }
          place(top + left, line(start: (0pt, 0pt), end: (w, h), stroke: 0.3pt + dbg))
          place(top + left, line(start: (w, 0pt), end: (0pt, h), stroke: 0.3pt + dbg))
          line-at(optical * h, 0.6pt, dbg)
          place(top + left, dx: m.left, dy: title-y, rect(
            width: text-w,
            height: title-h,
            stroke: 0.4pt + rgb("#00A0B0"),
          ))
          place(top + left, dx: m.left, dy: h - 14pt, text(
            size: 7pt,
            fill: dbg,
            font: "DejaVu Sans Mono",
          )[#canon · s=#calc.round(s, digits: 3) · fit=#calc.round(fit-factor, digits: 2) · col=#col-w.to-absolute() · gut=#g · hero=#calc.round(hero-h / 1mm, digits: 1)mm])
        }
      })
    },
  )

  if counter-reset { counter(page).update(1) }
}
