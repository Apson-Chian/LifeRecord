package ltd.apsonchian.liferecord

import android.os.Bundle
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import ltd.apsonchian.liferecord.ui.LifeRecordApp

class MainActivity : ComponentActivity() {
    private val model: AppViewModel by viewModels()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); enableEdgeToEdge()
        if(intent.getBooleanExtra("today", false)) model.todayRequest.value++
        setContent { LifeRecordApp(model) }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); if(intent.getBooleanExtra("today", false)) model.todayRequest.value++ }
    override fun onStart() { super.onStart(); model.foreground(true) }
    override fun onStop() { model.foreground(false); super.onStop() }
}
