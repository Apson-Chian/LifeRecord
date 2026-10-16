package ltd.apsonchian.liferecord

import android.os.Bundle
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.*
import androidx.core.view.WindowCompat
import ltd.apsonchian.liferecord.ui.LifeRecordApp

class MainActivity : ComponentActivity() {
    private val model: AppViewModel by viewModels()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); enableEdgeToEdge()
        if(intent.getBooleanExtra("today", false)) model.todayRequest.value++
        setContent {
            val appearance by model.appearance.collectAsState()
            val dark=appearance=="dark" || (appearance=="system" && isSystemInDarkTheme())
            SideEffect {
                WindowCompat.getInsetsController(window,window.decorView).apply {
                    isAppearanceLightStatusBars=!dark
                    isAppearanceLightNavigationBars=!dark
                }
            }
            LifeRecordApp(model)
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); if(intent.getBooleanExtra("today", false)) model.todayRequest.value++ }
    override fun onStart() { super.onStart(); model.foreground(true) }
    override fun onStop() { model.foreground(false); super.onStop() }
}
