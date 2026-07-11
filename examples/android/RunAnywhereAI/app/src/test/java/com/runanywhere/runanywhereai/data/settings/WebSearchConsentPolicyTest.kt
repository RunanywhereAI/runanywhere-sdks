package com.runanywhere.runanywhereai.data.settings

import com.runanywhere.runanywhereai.ui.components.webSearchDisclosureText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WebSearchConsentPolicyTest {
    @Test
    fun `legacy enabled preference cannot transfer without affirmative disclosure`() {
        val directScope = WebSearchConsentPolicy.routeFor("")!!.scope
        assertFalse(
            WebSearchConsentPolicy.permitsTransfer(
                WebSearchConsentState(
                    toolsEnabled = true,
                    acceptedScope = "",
                    currentScope = directScope,
                ),
            ),
        )
    }

    @Test
    fun `affirmative acceptance enables transfer`() {
        val directScope = WebSearchConsentPolicy.routeFor("")!!.scope
        assertTrue(
            WebSearchConsentPolicy.permitsTransfer(
                WebSearchConsentPolicy.accept(directScope),
            ),
        )
    }

    @Test
    fun `turning tools off revokes consent and requires a new acceptance`() {
        val revoked = WebSearchConsentPolicy.revoke()
        assertFalse(revoked.toolsEnabled)
        assertTrue(revoked.acceptedScope.isBlank())
        assertFalse(WebSearchConsentPolicy.permitsTransfer(revoked))
    }

    @Test
    fun `disclosure describes the actual direct and proxy transfer routes`() {
        val direct = webSearchDisclosureText(backendUrl = "")
        val proxy = webSearchDisclosureText(
            backendUrl = "https://search.partner.example/v1/search",
        )

        assertTrue(direct.contains("lite.duckduckgo.com and api.duckduckgo.com"))
        assertTrue(direct.contains("IP address"))
        assertTrue(direct.contains("No persistent device ID is sent"))
        assertTrue(proxy.contains("persistent device ID"))
        assertTrue(proxy.contains("search.partner.example"))
        assertTrue(proxy.contains("IP address"))
        assertTrue(direct.contains("No query is sent until you choose Allow"))
        assertTrue(proxy.contains("Turn Web & tools off to revoke"))
    }

    @Test
    fun `consent is scoped to direct versus proxy route and proxy destination`() {
        val direct = WebSearchConsentPolicy.routeFor("")!!
        val firstProxy = WebSearchConsentPolicy.routeFor(
            "https://search.first.example/v1/search",
        )!!
        val sameProxyDifferentPath = WebSearchConsentPolicy.routeFor(
            "https://SEARCH.FIRST.EXAMPLE/v2/search",
        )!!
        val secondProxy = WebSearchConsentPolicy.routeFor(
            "https://search.second.example/v1/search",
        )!!

        assertNotEquals(direct.scope, firstProxy.scope)
        assertEquals(firstProxy.scope, sameProxyDifferentPath.scope)
        assertNotEquals(firstProxy.scope, secondProxy.scope)
        assertFalse(
            WebSearchConsentPolicy.permitsTransfer(
                WebSearchConsentState(
                    toolsEnabled = true,
                    acceptedScope = direct.scope,
                    currentScope = firstProxy.scope,
                ),
            ),
        )
        assertFalse(
            WebSearchConsentPolicy.permitsTransfer(
                WebSearchConsentState(
                    toolsEnabled = true,
                    acceptedScope = firstProxy.scope,
                    currentScope = secondProxy.scope,
                ),
            ),
        )
    }

    @Test
    fun `invalid proxy configuration cannot produce an accepted route`() {
        assertNull(WebSearchConsentPolicy.routeFor("http://insecure.example/search"))
        assertNull(WebSearchConsentPolicy.routeFor("https:///missing-host"))
        assertNull(WebSearchConsentPolicy.routeFor("https://user:secret@example.com/search"))
        assertFalse(
            WebSearchConsentPolicy.permitsTransfer(
                WebSearchConsentPolicy.accept(currentScope = null),
            ),
        )
    }
}
