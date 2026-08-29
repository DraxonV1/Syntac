
package com.syntac

import android.app.IntentService
import android.content.Intent

class TermuxResultService : IntentService("TermuxResultService") {
    override fun onHandleIntent(intent: Intent?) {
        val commandId = intent?.getStringExtra(extraCommandId) ?: return
        val bundle = intent.getBundleExtra("result")
            ?: intent.getBundleExtra("com.termux.plugin_result_bundle")
        TermuxBridge.complete(commandId, bundle)
    }

    companion object {
        const val extraCommandId = "syntac.command_id"
    }
}
