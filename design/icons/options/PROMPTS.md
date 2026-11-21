# App icon prompts

The prompts that produced the icon options in this folder, in the order they were run (November 2026).
Each one was given to Codex (`gpt-6.2-sol`) as a standalone task, and it used its image generation skill.

- Image generation is not deterministic: running a prompt again gives a similar image, not the same one.
- Revision prompts point at an earlier draft as a reference image. `SCRATCH/` stands for the temporary
  folder used during the session. Drafts that were replaced by a revision are not kept in the repo; where a
  reference is kept, it is the file of the same name in this folder (as `.webp`).
- Every image is full-bleed square art (1024 px). The macOS rounded shape is applied afterwards.
- `contact-sheet-1.webp` to `contact-sheet-3.webp` show the options masked, at large, 64 px and 32 px sizes.

What was decided: G (couch) is the app icon, because that is the use case the app came from. The others are
kept as candidates for a possible icon picker in Settings. A was rejected, and "Aa" was dropped as content
because nobody types it.

## Round 1: first four concepts

### A: growing letters

Draft, not kept; replaced by its revision.

````text
Use your image generation skill to generate ONE app icon image, then save it as a PNG file. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility. You sit on a couch a few meters from your Mac, press a shortcut, and a huge, readable text editor appears over the screen so you can see what you type from across the room. The icon must say "text, made very large" at a glance, and stay readable at 32 px in the Dock.

Concept A, "growing letters": three lowercase-to-uppercase letter A's in a row on a shared baseline, growing sharply in size from left to right: a tiny "a", a medium "A", then a huge bold "A" that dominates the icon and nearly touches the top. Immediately to the right of the huge A, a thin vertical text-insertion caret (a blinking cursor bar) in a bright warm amber/orange, as tall as the huge A. Letters are clean white, in a heavy rounded sans-serif (SF Pro Rounded Bold feeling). Background: deep indigo-to-violet smooth vertical gradient, slightly lighter at the top, with a very subtle soft glow behind the big A. Modern macOS app icon style: simple, bold, flat-with-subtle-depth, soft shadow under the letters, no fine detail, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce, then it is fine).
- Full-bleed square background that fills the whole canvas edge to edge. Do NOT draw a rounded-rectangle icon shape, no device mockup, no border, no drop shadow around the icon, no transparent areas. I will apply the macOS rounded mask myself.
- Keep all important content inside the central 75% of the canvas so the mask does not clip it.
- No words or other text besides the three A glyphs. No watermark.

Save the final PNG to exactly this path:
SCRATCH/icons/round1/A-growing-letters.png

When done, reply with the absolute path of the saved file, its pixel dimensions, and one sentence on anything that deviates from the brief.
````

### B: overlay card

Draft, not kept; replaced by its revision.

````text
Use your image generation skill to generate ONE app icon image, then save it as a PNG file. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility. You sit on a couch a few meters from your Mac, press a shortcut, and a huge, readable text editor appears over the screen so you can see what you type from across the room; pressing Return puts the text into the small text field you started from. The icon must say "small text field becomes a big readable one" at a glance, and stay readable at 32 px in the Dock.

Concept B, "overlay card": near the bottom of the icon, a small, thin, pill-shaped text field (like a browser address bar) in a muted translucent dark blue, containing a few tiny pale dots suggesting unreadably small text. Rising out of it and dominating the upper two thirds of the icon, a large, bright, softly glowing white rounded card (a floating panel) containing a single huge bold dark-navy capital letter "A" followed by a thick vertical text-insertion caret in vivid electric blue. Two faint diverging lines or a soft light cone connect the small field up to the big card, suggesting it was projected/enlarged from the field. Background: dark midnight-navy to deep teal-blue smooth gradient. Modern macOS app icon style: simple, bold, clean geometry, subtle depth and soft shadows, slight glass feel on the card, no fine detail, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background that fills the whole canvas edge to edge. Do NOT draw a rounded-rectangle icon shape, no device mockup, no border, no drop shadow around the icon, no transparent areas. I will apply the macOS rounded mask myself.
- Keep all important content inside the central 75% of the canvas so the mask does not clip it.
- No words or text besides the single "A" glyph. No watermark.

Save the final PNG to exactly this path:
SCRATCH/icons/round1/B-overlay-card.png

When done, reply with the absolute path of the saved file, its pixel dimensions, and one sentence on anything that deviates from the brief.
````

### C: giant caret

Draft, not kept; replaced by its revision.

````text
Use your image generation skill to generate ONE app icon image, then save it as a PNG file. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility. You sit on a couch a few meters from your Mac, press a shortcut, and a huge, readable text editor appears over the screen so you can see what you type from across the room. The icon must say "typing, at a huge size" at a glance, and stay readable at 32 px in the Dock.

Concept C, "giant T and caret": one enormous, heavy, geometric capital letter "T" in warm off-white, so large that it fills most of the icon (its crossbar spans about 70% of the width). Right next to its stem on the right side, a thick, rounded vertical text-insertion caret (cursor bar) glowing in bright mint-green / lime, the same height as the T, with a soft glow as if it is blinking on. The T has a subtle long soft shadow falling down-right to give depth. Background: rich warm gradient from coral-orange at the top-left to deep magenta-plum at the bottom-right. Modern macOS app icon style: very simple, very bold, two shapes only, flat with subtle depth, no fine detail, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background that fills the whole canvas edge to edge. Do NOT draw a rounded-rectangle icon shape, no device mockup, no border, no drop shadow around the icon, no transparent areas. I will apply the macOS rounded mask myself.
- Keep all important content inside the central 75% of the canvas so the mask does not clip it.
- No words or text besides the single "T" glyph. No watermark.

Save the final PNG to exactly this path:
SCRATCH/icons/round1/C-giant-caret.png

When done, reply with the absolute path of the saved file, its pixel dimensions, and one sentence on anything that deviates from the brief.
````

### D: glass lens

Draft, not kept; replaced by its revision.

````text
Use your image generation skill to generate ONE app icon image, then save it as a PNG file. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility. Press a shortcut and a huge, readable text editor appears over the screen so you can read what you type from across the room; a second shortcut shows any text under the mouse pointer in a very large size. The icon must say "small text, shown large" at a glance, and stay readable at 32 px in the Dock.

Concept D, "glass lens": several horizontal rows of small, pale, rounded bars (abstract placeholder lines of tiny text) run across the icon. Over the center sits a large rounded-square pane of clear glass (macOS "liquid glass" style: translucent, bright rim highlight, gentle refraction, soft shadow underneath), tilted not at all, covering about 60% of the icon. Inside the glass pane the abstract lines turn into two huge crisp white letters "Aa" in a heavy rounded sans-serif, clearly magnified, sharp and bright. No magnifying-glass handle, no circle loupe: it is a floating glass card. Background: smooth gradient from bright sky blue at the top to deep royal blue at the bottom. Modern macOS app icon style: simple, bold, clean, subtle depth, no fine detail, no photorealistic clutter.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background that fills the whole canvas edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no device mockup, no border, no drop shadow around the icon, no transparent areas. I will apply the macOS rounded mask myself.
- Keep all important content inside the central 75% of the canvas so the mask does not clip it.
- No words or text besides the "Aa" glyphs. No watermark.

Save the final PNG to exactly this path:
SCRATCH/icons/round1/D-glass-lens.png

When done, reply with the absolute path of the saved file, its pixel dimensions, and one sentence on anything that deviates from the brief.
````

## Round 2: revisions of A to D

### A2: growing letters

Saved as `A2-growing-letters.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility: press a shortcut and a huge, readable text editor appears over the screen so you can read what you type from across the room. The icon must say "text, made very large" and stay readable at 32 px.

A first draft exists; look at it first and use it as the reference (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round1/A-growing-letters.png

The draft shows white rounded letters "a A A" growing in size on one baseline with an orange caret on an indigo-violet gradient. Keep that style, typeface feeling and palette. Change these things:
1. Composition: the group sat too low and too small, with a large empty area above. Make the group much bigger and optically centered both vertically and horizontally: the whole group (letters + caret) should span about 72% of the canvas width, and the huge A should be about 60% of the canvas height, vertically centered.
2. Only two letters: remove the medium A. Keep a tiny lowercase "a" at the left (about one fifth the height of the big A, sitting on the same baseline) and the huge bold "A". The size jump should feel dramatic.
3. Caret: keep it warm amber, slightly thicker (about as thick as one third of the A's stroke), rounded ends, with a soft amber glow, a small gap from the A, same height as the A.
4. Background: keep the indigo-to-violet gradient but make it a little richer and less flat, with a soft lighter radial glow behind the big A. No other elements.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- All content inside the central 75% of the canvas.
- No text besides the "a" and "A" glyphs. No watermark.

Save to exactly:
SCRATCH/icons/round2/A2-growing-letters.png
(create the round2 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### B2: overlay card

Saved as `B2-overlay-card.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility: with the cursor in a small text field, press a shortcut and a huge, readable text editor appears over the screen so you can read what you type from across the room; Return puts the text back into the small field. The icon must say "small text field becomes a big readable one" and stay readable at 32 px.

A first draft exists; look at it first and use it as the reference (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round1/B-overlay-card.png

The draft shows a small translucent pill-shaped text field at the bottom with three dots, a soft cyan light cone rising from it, and a large glowing white rounded card containing a dark navy "A" and a blue caret, on a navy-to-teal gradient. Keep that concept, the glow, the light cone and the palette. Change these things:
1. IMPORTANT: the dark "A" followed by the thick blue bar reads as the word "AI". That must not happen. Replace the card content with the two letters "Aa" (capital A, lowercase a) in dark navy, heavy rounded sans-serif (SF Pro Rounded Bold feeling), followed by a clearly thinner caret in warm amber/orange with rounded ends, taller than the letters (extending a little above the cap height and below the baseline) and separated by a visible gap, so it is unmistakably a text cursor and not a letter.
2. Inside the small pill at the bottom, replace the three dots with a miniature version of the same content: tiny pale "Aa" and a tiny amber caret, so it is obvious the big card is the enlarged version of the small field.
3. Safe area: the card was too wide and the pill too low. Make the card about 64% of the canvas width and move the pill up, so the entire composition (card, cone, pill) fits inside the central 75% of the canvas with the group optically centered.
4. Give the card slightly more depth: a soft shadow below it and a subtle glass rim highlight. Keep it simple.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No text besides the "Aa" glyphs (big and miniature). No watermark.

Save to exactly:
SCRATCH/icons/round2/B2-overlay-card.png
(create the round2 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### C2: giant T

Saved as `C2-giant-T.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility: press a shortcut and a huge, readable text editor appears over the screen so you can read what you type from across the room (often while watching video on the couch). The icon must say "typing, at a huge size" and stay readable at 32 px.

A first draft exists; look at it first and use it as the reference for the shapes (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round1/C-giant-caret.png

The draft shows one enormous flat off-white geometric capital "T" with a fat glowing lime-green bar to its right on a coral-to-plum gradient. Keep the idea of one giant heavy geometric T plus a text caret, and the subtle long soft shadow. Change these things:
1. IMPORTANT: the fat bar standing beside the T makes it read as the letters "TI". Instead, make the caret clearly a text cursor: much slimmer (about one quarter of the T stem's width), with rounded ends, and place it tucked in the empty notch under the right half of the crossbar, to the right of the stem with a clear gap. It runs from just below the crossbar down to the T's baseline, so the T and caret together form one compact block.
2. New palette: background is a dark cinematic gradient, deep graphite / near-black with a hint of midnight blue, slightly lighter toward the top-left, like a dim living room lit by a screen. The T is warm off-white with very slightly rounded corners. The caret is warm amber-orange with a soft glow that subtly lights the adjacent edge of the T stem.
3. Safe area: the T was too large. The T's crossbar should span about 56% of the canvas width and the T's height about 56% of the canvas height, optically centered, with everything inside the central 72% of the canvas.
4. Still only two shapes. No extra elements.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No text besides the single "T" glyph. No watermark.

Save to exactly:
SCRATCH/icons/round2/C2-giant-T.png
(create the round2 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### D2: glass lens

Saved as `D2-glass-lens.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility: press a shortcut and any text under the pointer, or the text you are typing, is shown in a very large size so you can read it from across the room. The icon must say "small text, shown large" and stay readable at 32 px.

A first draft exists; look at it first and use it as the reference (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round1/D-glass-lens.png

The draft shows rows of small pale placeholder text bars on a blue gradient, with a clear glass rounded-square pane in the center containing big white "Aa". Keep the concept and the glass quality. Change these things:
1. It is too monochrome blue and looks like a generic font app. New palette: background gradient from warm sunset orange at the top to hot pink / magenta at the bottom. Placeholder text bars are soft translucent white. The glass pane is clear with a bright rim highlight and a faint warm tint; the big letters stay pure white.
2. Make the magnification obvious: the rows of small bars continue up to the pane edges, and inside the pane there are NO bars at all, only the big content. The pane should feel like it lifts off the page, with a clear soft shadow underneath.
3. Content inside the pane: big white "Aa" in heavy rounded sans-serif, followed by a slim vertical text caret in white with rounded ends, slightly taller than the capital A, separated by a clear gap (so it reads as a cursor, not as a letter).
4. Fewer, slightly thicker bars: about 5 rows total, so they survive at small sizes. No bars in the outer 10% margin of the canvas.
5. Pane about 62% of canvas width, optically centered; everything important inside the central 75% of the canvas.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No text besides the "Aa" glyphs. No watermark.

Save to exactly:
SCRATCH/icons/round2/D2-glass-lens.png
(create the round2 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

## Round 3: concepts without "Aa"

### E: eye chart

Draft, not kept; replaced by its revision.

````text
Use your image generation skill to generate ONE app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from across the room (on the couch, several meters from the screen). Press a shortcut and what you type, or the text under the pointer, is shown huge so it can be read from a distance. The icon should tell the story "readable from far away" and stay legible at 32 px.

Concept E, "eye chart": a playful take on an optician's eye-test chart (Snellen chart), the universal symbol for "can you read this from over there?". A clean off-white rounded card, portrait-ish (about 58% of canvas width, 66% of canvas height), floating in the center with a soft shadow. On the card: the top row is ONE enormous heavy geometric capital "T" in dark graphite, taking about half of the card's height, immediately followed on its right by a slim, rounded, glowing amber-orange vertical text caret (a text cursor) the same height as the T, with a clear gap, so it is obviously a cursor and not a letter. Below it, three rows that shrink quickly like an eye chart: row 2 has three medium dark rounded blocks/letters, row 3 has five smaller ones, row 4 is a line of tiny dots. The lower rows should be abstract simple dark rounded bars or dots rather than real readable letters, so the only real glyph is the T. The message: the top line, the one being typed, is huge.

Background: a warm but restrained gradient, soft coral/peach at the top to muted dusty rose/plum at the bottom. Eye-catching but not neon: moderate saturation, no hot pink.

Style: modern macOS app icon, simple, bold, clean geometry, flat with subtle depth, soft shadows, no fine detail, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- All content inside the central 75% of the canvas.
- No text besides the single "T". No watermark.

Save to exactly:
SCRATCH/icons/round3/E-eye-chart.png
(create the round3 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### F: oversized caret

Draft, not kept; replaced by its revision.

````text
Use your image generation skill to generate ONE app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility. With the cursor in any small text field (a browser address bar, a search box), you press a shortcut and a huge text editor appears so you can read what you type from across the room. The icon should tell the story "the tiny text field, blown up huge" with no letters at all, and stay legible at 32 px.

Concept F, "the cursor that outgrew its field": in the lower third of the icon sits a small, ordinary pill-shaped text field (rounded capsule outline, about 50% of canvas width, thin, pale translucent fill with a soft light border), with a tiny magnifier (search) glyph at its left end and two or three tiny pale dots as typed characters. From the spot inside the field where the text cursor would be, a gigantic text caret shoots up: a thick, rounded vertical bar in glowing warm amber-orange, starting inside the pill and rising far above it to about 62% of the canvas height, bursting out through the top of the field as if the cursor was scaled up 20x. The caret is the hero of the icon. It has a soft warm glow that lights the pill and the background around it. A few very subtle thin lines fan out upward from the pill beside the caret to suggest growth/zoom (optional, keep minimal).

Background: dark cinematic gradient, deep graphite / near-black with a hint of midnight blue, slightly lighter at the top-left, like a dim living room lit by a screen.

Style: modern macOS app icon, very simple and bold, two main shapes, flat with subtle depth, soft glow and shadows, no fine detail, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- The whole composition optically centered, all content inside the central 75% of the canvas.
- No letters, no words, no watermark.

Save to exactly:
SCRATCH/icons/round3/F-oversized-caret.png
(create the round3 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### G: couch and screen

Draft, not kept; replaced by its revision.

````text
Use your image generation skill to generate ONE app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from the couch, several meters from the screen, with a wireless keyboard. Press a shortcut and what you type is shown huge on the screen so you can read it from across the room. The icon should tell that story: "typing from the couch, and the text is big enough to read". It must stay legible at 32 px, so keep it to two simple shapes.

Concept G, "couch and screen": a minimal, almost pictogram-like scene seen from behind a sofa. In the bottom third: the back of a simple rounded sofa as one bold, dark, soft silhouette (a wide rounded rectangle backrest with two rounded armrests, no person, no cushions detail), spanning about 66% of the canvas width. Above it, in the upper two thirds: a wide, softly glowing screen (rounded rectangle, about 62% of canvas width, off-white / very pale warm light) that shows one huge line being typed: three or four very thick dark rounded bars of different lengths in a row (abstract "words", not real letters) followed by a thick glowing amber-orange vertical text caret taller than the bars. The line fills almost the whole width of the screen, clearly oversized. The screen's light softly spills onto the top edge of the sofa as a warm rim light.

Background: dim evening living-room mood, a smooth gradient from deep indigo-navy at the top to dark plum at the bottom, restrained saturation.

Style: modern macOS app icon, simple, bold, clean rounded geometry, flat with subtle depth, soft glow and shadows, no fine detail, no texture, no photorealism, no people.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- All content inside the central 75% of the canvas, optically centered.
- No letters, no words, no watermark.

Save to exactly:
SCRATCH/icons/round3/G-couch-screen.png
(create the round3 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### H: search field blown up

Draft, not kept; replaced by its revision.

````text
Use your image generation skill to generate ONE app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility. With the cursor in any small text field (a browser address bar, a search box), you press a shortcut and a huge text editor appears over the screen so you can read what you type from across the room; Return puts the text back into the small field. The icon should tell the story "the same text field, small and then huge" and stay legible at 32 px.

An earlier draft of this concept exists; look at it first for the layout, glow and light cone (use it as a reference image if your skill supports that, otherwise regenerate from this description):
SCRATCH/icons/round2/B2-overlay-card.png

That draft has a small pill text field at the bottom, a light cone rising from it, and a big glowing white card with "Aa" and an amber caret. Keep the layout idea (small field below, soft light cone, big card above) but change the content and palette:
1. No "Aa" anywhere; nobody types "Aa". Make both shapes read as the SAME search field at two sizes. The small pill at the bottom is a search field: a tiny magnifier (search) glyph at its left, then a tiny short pale squiggle/dots as unreadably small typed text, then a tiny caret. The big card above is the same field hugely enlarged: a wide pill-shaped / strongly rounded white panel containing a large dark magnifier glyph at the left, then three very thick dark rounded bars of different lengths as abstract typed words (no real letters), then a thick glowing amber-orange text caret taller than the bars. The big version should be about 6x the size of the small one so the contrast is dramatic.
2. Palette: warm and eye-catching but restrained. Background gradient from soft coral-orange at the top to muted raspberry / plum at the bottom, moderate saturation, no neon, no hot pink. The big panel is bright warm white with a soft glow and a soft shadow; the small pill is translucent white. The light cone is a soft warm white.
3. The whole composition (panel, cone, pill) optically centered and inside the central 75% of the canvas; big panel about 66% of canvas width.

Style: modern macOS app icon, simple, bold, clean rounded geometry, subtle depth, slight glass rim on the panel, no fine detail, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No letters, no words, no watermark.

Save to exactly:
SCRATCH/icons/round3/H-search-field.png
(create the round3 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

## Round 4: revisions of E to H

### E2: eye chart

Saved as `E2-eye-chart.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from across the room. Press a shortcut and what you type is shown huge so it can be read from a distance. The icon is a playful optician's eye-test chart (Snellen chart): "can you read this from over there?". It must stay legible at 32 px.

A first draft exists; look at it first and use it as the reference (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round3/E-eye-chart.png

The draft has an off-white rounded card on a coral-to-dusty-plum gradient, with a huge dark "T", an orange caret beside it, and rows of abstract dark bars and dots below. Keep the card, the background palette and the flat clean style. Change these things:
1. It reads as a document with a list, not as an eye chart. Make it unmistakably an eye chart by using REAL letters that shrink row by row, centered on the card, in a heavy geometric sans-serif, dark graphite:
   - Row 1: one enormous capital "T" (about 42% of the card height).
   - Row 2: the letters "E X T" with wide letter spacing, about 40% the height of the big T. (Together the rows read T / E X T, i.e. "TEXT".)
   - Row 3: a row of 7 very small dark dots (letters too small to read).
   That is all: exactly three rows.
2. Caret: the caret standing beside the big T made it read like "TI". Instead make the caret slim (about one quarter of the T stem's width), rounded ends, glowing amber-orange, and tuck it into the empty notch under the right half of the T's crossbar, to the right of the stem with a clear gap, running from just below the crossbar down to the T's baseline.
3. Size: the card should be about 56% of the canvas width and 64% of the canvas height, optically centered, with a soft shadow; everything inside the central 75% of the canvas.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No text besides the letters T, E, X, T described above. No watermark.

Save to exactly:
SCRATCH/icons/round4/E2-eye-chart.png
(create the round4 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### F2: oversized caret

Saved as `F2-oversized-caret.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility. With the cursor in any small text field, you press a shortcut and a huge text editor appears so you can read what you type from across the room. The icon shows "the text cursor that outgrew its small text field". It must stay legible at 32 px.

A first draft exists; look at it first and use it as the reference (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round3/F-oversized-caret.png

The draft has a faint glass pill-shaped search field near the bottom of a dark graphite/midnight-blue background, and a huge glowing amber caret rising out of it. Keep the dark background, the amber glow and the idea. Change these things:
1. The text field is too faint and will disappear at small sizes. Make it a solid, clearly visible field: an opaque warm off-white pill with a soft shadow, about 54% of the canvas width and about 13% of the canvas height.
2. Inside the pill, from left to right: a small dark magnifier (search) glyph, then three short thick dark rounded bars as the typed words (abstract, not letters), and then, immediately after the last bar with a small gap, the caret. The caret must clearly belong to that line of text: it starts at the bottom inside of the pill right where a normal cursor would sit after the last word, and from there grows absurdly tall, shooting up through the top edge of the pill to about 58% of the canvas height. Thick, rounded ends, glowing warm amber-orange, casting warm light on the pill.
3. So the caret is right of center inside the pill (after the text), not in the middle of empty space. Balance the composition so the whole group is still optically centered in the canvas.
4. Everything inside the central 75% of the canvas.

Style: modern macOS app icon, very simple and bold, flat with subtle depth, soft glow and shadows, no fine detail, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No letters, no words, no watermark.

Save to exactly:
SCRATCH/icons/round4/F2-oversized-caret.png
(create the round4 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### G2: couch and screen

Saved as `G2-couch-screen.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from the couch, several meters from the screen. Press a shortcut and what you type is shown huge on the screen so you can read it from across the room. The icon shows the back of a sofa facing a glowing screen with oversized text. It must stay legible at 32 px.

A first draft exists; look at it first and use it as the reference (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round3/G-couch-screen.png

The draft has a dark rounded sofa silhouette at the bottom with a warm rim light, a glowing cream screen above it showing three thin dark bars and an orange caret, on an indigo-to-plum gradient. Keep the scene, the palette, the glow and the rim light. Change these things:
1. Safe area: everything is too wide and will be clipped by the icon mask. Scale the scene down: the screen about 60% of the canvas width, the sofa about 64% of the canvas width, the whole group optically centered and entirely inside the central 75% of the canvas. Leave a clear gap of background around all sides.
2. The text on the screen is too thin; it reads as dashes, not as huge text. Replace the three thin bars with two very chunky dark rounded bars (each about 30% of the screen's height tall, one longer and one shorter), followed by a thick glowing amber-orange caret that is about 55% of the screen's height. The line should nearly fill the screen so it feels oversized and easy to read from the sofa.
3. Make the sofa a little more recognizable as a sofa while staying a simple silhouette: a backrest with softly rounded top corners and two rounded armrests slightly lower than the backrest, plus a subtle vertical seam line in the middle of the backrest. No people, no other furniture.
4. Screen: keep the soft glow, add a very thin darker bezel edge so it reads as a screen rather than a card.

Style: modern macOS app icon, simple, bold, clean rounded geometry, flat with subtle depth, no fine detail, no texture, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No letters, no words, no watermark.

Save to exactly:
SCRATCH/icons/round4/G2-couch-screen.png
(create the round4 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### H2: field small and huge

Saved as `H2-field-small-huge.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility. With the cursor in any small text field, you press a shortcut and a huge text editor appears over the screen so you can read what you type from across the room; Return puts the text back into the small field. The icon shows the same text field twice: tiny, and hugely enlarged. It must stay legible at 32 px. It must NOT look like a search app.

A first draft exists; look at it first and use it as the reference (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round3/H-search-field.png

The draft has a big cream pill-shaped search field (magnifier glyph, three dark bars, orange caret) glowing above a small copy of the same field, connected by a soft light cone, on a coral-to-plum gradient. Keep the palette, the glow, the cone and the idea of the same field at two sizes. Change these things:
1. Safe area: the big field is too wide and will be clipped by the icon mask. Make the big panel about 64% of the canvas width, and make it taller relative to its width: a strongly rounded rectangle (not a thin pill), about 34% of the canvas height, like a large floating editor panel.
2. Remove the magnifier glyphs from both fields; they make it look like a search app. The big panel contains only: two very chunky dark plum rounded bars on one line (abstract typed words, each about 30% of the panel's height tall, one longer, one shorter) followed by a thick glowing amber-orange caret about 55% of the panel's height. The text should nearly fill the panel so it feels huge.
3. The small field at the bottom stays a thin pill (an ordinary text field, about 22% of the canvas width) with the same content in miniature: two tiny bars and a tiny amber caret. The size contrast between the two should be dramatic.
4. Move the small pill up so the whole group (panel, cone, pill) is optically centered and entirely inside the central 75% of the canvas.

Style: modern macOS app icon, simple, bold, clean rounded geometry, subtle depth, slight glass rim on the panel, soft shadow under it, no fine detail, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No letters, no words, no watermark.

Save to exactly:
SCRATCH/icons/round4/H2-field-small-huge.png
(create the round4 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

## Round 5: real-world metaphors

### I: billboard

Saved as `I-billboard.webp`.

````text
Use your image generation skill to generate ONE app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from across the room. Press a shortcut and what you type is shown huge so it can be read from far away. The icon uses a playful real-world metaphor for "text big enough to read from a distance". It must stay legible at 32 px, so keep it to a few bold shapes.

Concept I, "billboard": a classic roadside billboard seen straight on, simplified to a pictogram. A wide off-white rounded-rectangle sign board (about 62% of canvas width, 36% of canvas height) with a slim dark frame, standing on one sturdy dark central post, with two tiny lamp arms on top casting soft warm light down onto the board. On the board, filling it: one enormous heavy geometric capital "T" in dark graphite, with a slim glowing amber-orange text caret (rounded ends) tucked in the notch under the right half of the T's crossbar, right of the stem with a clear gap, running from below the crossbar to the baseline, so it reads as a text cursor, as if someone is typing on the billboard. Below the billboard at the very bottom of the composition, a low dark rolling-hill horizon silhouette with one tiny tree or tiny car silhouette to give the board a sense of huge scale.

Background: dusk sky gradient, warm peach/coral near the horizon rising to muted dusty violet at the top, restrained saturation (eye-catching but not neon).

Style: modern macOS app icon, simple, bold, clean rounded geometry, flat with subtle depth, soft glow and shadows, no fine detail, no texture, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself. (The horizon may run edge to edge, but the billboard and post must be inside the central 75% of the canvas, optically centered.)
- No text besides the single "T". No watermark.

Save to exactly:
SCRATCH/icons/round5/I-billboard.png
(create the round5 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### J: searchlight signal

Saved as `J-searchlight.webp`.

````text
Use your image generation skill to generate ONE app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from across the room. With the cursor in a small text field, press a shortcut and what you type is shown huge so it can be read from far away. The icon uses a playful real-world metaphor for "small text projected huge". It must stay legible at 32 px, so keep it to a few bold shapes.

Concept J, "searchlight signal": a night-sky signal, like a searchlight projecting a symbol onto the clouds. At the bottom center, a small pill-shaped text field (an ordinary input field: off-white capsule with two tiny dark bars and a tiny amber caret inside, about 24% of the canvas width) acts as the lamp. From it a soft cone of warm light widens upward into the sky. At the top of the beam, on a soft round patch of lit cloud (a bright warm-white disc with slightly fluffy, simple cloud edges, about 56% of the canvas width), the projected symbol appears huge: one enormous heavy geometric capital "T" in dark navy silhouette with a slim glowing amber-orange text caret (rounded ends) tucked in the notch under the right half of the T's crossbar, right of the stem with a clear gap. At the very bottom, flanking the small field, a low simple dark skyline silhouette of a few rooftops (very simple blocks, 3 to 5 tiny lit windows at most).

Background: deep night sky gradient, midnight navy at the top to a slightly lighter indigo-teal near the horizon, a few tiny soft stars (no more than 6).

Style: modern macOS app icon, simple, bold, clean rounded geometry, flat with subtle depth, soft glow, no fine detail, no texture, no photorealism. Do not make it resemble any comic-book hero logo: the projected mark is just the letter T with a text cursor on a round cloud disc.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself. (The skyline may run edge to edge, but the disc, beam and field must be inside the central 75% of the canvas, optically centered.)
- No text besides the single "T". No watermark.

Save to exactly:
SCRATCH/icons/round5/J-searchlight.png
(create the round5 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### K: keyboard and giant letter

Saved as `K-keyboard-letter.webp`.

````text
Use your image generation skill to generate ONE app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from the couch with a wireless keyboard on your lap. Press a shortcut and what you type is shown huge so it can be read from across the room. The icon tells the story "a small keyboard, and the letter you just typed appears gigantic". It must stay legible at 32 px, so keep it to a few bold shapes.

Concept K, "one key, giant letter": in the lower third, a compact wireless keyboard seen from slightly above, simplified to a pictogram: a low, wide, light-gray/aluminium rounded slab (about 62% of canvas width) with three rows of simple rounded square keys in soft white. Exactly one key, right of center, is pressed and glows warm amber-orange. From that glowing key, a soft warm light rises and above the keyboard, filling the upper two thirds, floats one gigantic heavy geometric capital "T" in warm off-white (about 46% of the canvas height), with a slim glowing amber-orange text caret (rounded ends) tucked in the notch under the right half of the T's crossbar, right of the stem with a clear gap, running from below the crossbar to the baseline. The T is far bigger than the whole keyboard is tall: the contrast between the small key and the giant letter is the point. Subtle soft shadow under the keyboard.

Background: dark cinematic gradient, deep graphite / near-black with a hint of midnight blue, slightly lighter toward the top-left, like a dim living room lit by a screen.

Style: modern macOS app icon, simple, bold, clean rounded geometry, flat with subtle depth, soft glow and shadows, no fine detail, no key legends, no texture, no photorealism.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- All content inside the central 75% of the canvas, optically centered.
- No text besides the single "T" (no letters on the keys). No watermark.

Save to exactly:
SCRATCH/icons/round5/K-keyboard-letter.png
(create the round5 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### L: blimp

Saved as `L-blimp.webp`.

````text
Use your image generation skill to generate ONE app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from across the room. Press a shortcut and what you type is shown huge so it can be read from far away. The icon uses a playful, friendly real-world metaphor for "text so big you can read it from miles away". It must stay legible at 32 px, so keep it to a few bold shapes.

Concept L, "blimp": a charming, simplified airship (blimp) floating in the sky, seen from the side, as a clean pictogram. The blimp body is a big smooth off-white/cream ellipse (about 66% of canvas width) with a small dark gondola underneath and simple rounded tail fins at the left end in muted coral. On the side of the blimp, as its giant display, one enormous heavy geometric capital "T" in dark graphite with a slim glowing amber-orange text caret (rounded ends) tucked in the notch under the right half of the T's crossbar, right of the stem with a clear gap, running from below the crossbar to the baseline, as if text is being typed on the blimp. Two or three very simple soft clouds partly behind and below the blimp. No ground, no city.

Background: soft sky gradient, warm peach at the bottom to muted teal-blue at the top, restrained saturation (pleasant and eye-catching but not neon).

Style: modern macOS app icon, simple, bold, clean rounded geometry, flat with subtle depth and soft shading on the blimp body, soft shadows, no fine detail, no texture, no photorealism, no brand markings.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- The blimp entirely inside the central 75% of the canvas, optically centered.
- No text besides the single "T". No watermark.

Save to exactly:
SCRATCH/icons/round5/L-blimp.png
(create the round5 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

### G3: couch with giant T

Saved as `G3-couch-T.webp`.

````text
Use your image generation skill to generate ONE revised app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from the couch, several meters from the screen. Press a shortcut and what you type is shown huge on the screen so you can read it from across the room. The icon shows the back of a sofa facing a glowing screen with oversized text. It must stay legible at 32 px.

An existing draft is the reference; look at it first (image-to-image edit if your skill supports a reference image, otherwise regenerate from this description):
SCRATCH/icons/round4/G2-couch-screen.png

The draft has a dark rounded sofa silhouette at the bottom with a warm rim light and a center seam, a glowing cream screen above it showing two chunky dark bars and an orange caret, on an indigo-to-plum gradient. Keep the scene, the palette, the screen glow and the rim light on the sofa. Change these things:
1. Replace the two dark bars on the screen with a real letter: one enormous heavy geometric capital "T" in dark plum/graphite, centered on the screen and filling about 78% of the screen's height, with a slim glowing amber-orange text caret (rounded ends) tucked in the notch under the right half of the T's crossbar, right of the stem with a clear gap, running from below the crossbar down to the T's baseline. Nothing else on the screen.
2. Make the screen a bit taller to fit the T: about 58% of the canvas width and 40% of the canvas height.
3. Make the sofa read more clearly as a sofa at small sizes: slightly taller armrests with rounded tops, a clear backrest, and two back cushions separated by the center seam. Still a simple dark silhouette with the warm rim light on top.
4. Center the whole scene vertically (it sat slightly low) and keep everything inside the central 75% of the canvas.

Style: modern macOS app icon, simple, bold, clean rounded geometry, flat with subtle depth, no fine detail, no texture, no photorealism, no people.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No text besides the single "T". No watermark.

Save to exactly:
SCRATCH/icons/round5/G3-couch-T.png
(create the round5 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````

## Round 6: polish of the chosen icon

### G4: couch polish

Saved as `../AppIcon-master.png`.

````text
Use your image generation skill to generate ONE polished app icon image and save it as a PNG. Do not write code or touch any repository; this is purely an image generation job.

Context: "LargeText" is a macOS utility for using a Mac from the couch, several meters from the screen. Press a shortcut and what you type is shown huge on the screen so you can read it from across the room. This icon has been chosen as the final app icon; this is a polish pass, so change as little as possible.

The chosen image is the reference; look at it first and edit it (image-to-image edit with the reference image if your skill supports it; otherwise regenerate it as faithfully as you can):
SCRATCH/icons/round5/G3-couch-T.png

It shows: an indigo (top) to plum-purple (bottom) gradient background; a glowing cream rounded-rectangle screen with a thin darker bezel edge and a warm orange outer glow; on the screen one enormous heavy geometric dark-plum capital "T" with a slim glowing amber-orange text caret (rounded ends) tucked under the right half of the crossbar, right of the stem; below the screen, the back of a sofa as a dark plum silhouette with two back cushions, a center seam, two rounded armrests, and a warm orange rim light along its top edges.

Keep ALL of that: same composition, same shapes, same palette, same T and caret, same glow. Make only these polish changes:
1. Vertical centering: the scene sits slightly low. Move the whole group (screen + sofa) up so it is optically centered: equal empty background above the screen's glow and below the sofa.
2. Sofa legibility at small sizes: the sofa blends into the dark background, especially at the bottom. Make the sofa body a little lighter and slightly warmer than the background (a mid plum/aubergine that clearly separates from the background everywhere, including its bottom edge and armrests), keep the warm rim light on top and make it slightly brighter and a touch thicker. The sofa must be recognisable as a sofa when the icon is shrunk to 32 px.
3. Slightly more gap between the caret and the T's stem (they nearly touch): the gap should be about the caret's own width.
4. Crisp, clean edges everywhere; perfectly smooth gradient background with no banding, no noise, no vignette corners.
5. Keep everything inside the central 75% of the canvas: screen about 58% of canvas width, sofa about 64% of canvas width.

Hard requirements:
- Square image, 1024x1024 (or the closest square size you can produce).
- Full-bleed square background edge to edge. Do NOT draw a rounded-rectangle icon shape around the whole image, no mockup, no border, no transparent areas. I will apply the macOS rounded mask myself.
- No text besides the single "T". No watermark. No people.

Save to exactly:
SCRATCH/icons/round6/G4-couch-T.png
(create the round6 folder if missing)

When done, reply with the absolute path, pixel dimensions, and one sentence on anything that deviates from the brief.
````
