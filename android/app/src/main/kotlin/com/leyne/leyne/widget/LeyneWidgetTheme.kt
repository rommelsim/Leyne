// Widget colour tokens — mirrored from WidgetShared.swift palette.
//
// Glance 1.1.1's ColorProvider has only two overloads — ColorProvider(Color)
// and ColorProvider(@ColorRes resId) — there is NO ColorProvider(day, night).
// So day/night theming is done the canonical Android way: the resource-id
// overload resolves @color/w_* against res/values/colors.xml (light) or
// res/values-night/colors.xml (dark) at draw time, based on the launcher's
// dark-mode state. This also preserves the true iOS alpha values (dim/faint/
// line) rather than pre-mixing them against a surface.

package com.leyne.leyne.widget

import androidx.glance.unit.ColorProvider
import com.leyne.leyne.R

/** Widget card background. Light #FFFFFF / Dark #1A1A1A */
val wBg = ColorProvider(R.color.w_bg)

/** Primary ink. Light #111111 / Dark #FFFFFF */
val wFg = ColorProvider(R.color.w_fg)

/** Secondary ink (fg @ 0.65). */
val wDim = ColorProvider(R.color.w_dim)

/** Tertiary ink (fg @ 0.45). */
val wFaint = ColorProvider(R.color.w_faint)

/** Hairline divider (fg @ 0.10). */
val wLine = ColorProvider(R.color.w_line)

/** "Arriving" ink fill — same as wFg (monochrome signal, not a hue). */
val wLive = ColorProvider(R.color.w_live)

/** Ink-tinted row background for arriving rows. Light #EDEDED / Dark #242424 */
val wLiveBg = ColorProvider(R.color.w_live_bg)

/** Text on top of an ink-filled badge / arriving row. Light #FFFFFF / Dark #111111 */
val wOnLive = ColorProvider(R.color.w_on_live)
