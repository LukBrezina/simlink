package sk.brezinovi.simlink

import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebFragment

/** Default web destination — renders the Rails screens. Matches the `uri` in
 *  assets/json/configuration.json. */
@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
class WebFragment : HotwireWebFragment()
