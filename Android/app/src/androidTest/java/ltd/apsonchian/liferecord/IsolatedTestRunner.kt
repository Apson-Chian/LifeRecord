package ltd.apsonchian.liferecord

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.test.core.app.ApplicationProvider
import androidx.test.runner.AndroidJUnitRunner

class IsolatedTestRunner : AndroidJUnitRunner() {
    override fun onCreate(arguments: Bundle?) {
        check(targetContext.packageName == IsolatedLifeRecordApplication.PACKAGE)
        check(targetContext.checkSelfPermission(Manifest.permission.INTERNET) == PackageManager.PERMISSION_DENIED)
        super.onCreate(arguments)
    }
}

object TestIsolation {
    fun app(): IsolatedLifeRecordApplication {
        val app = ApplicationProvider.getApplicationContext<IsolatedLifeRecordApplication>()
        check(app.packageName == IsolatedLifeRecordApplication.PACKAGE)
        check(app.checkSelfPermission(Manifest.permission.INTERNET) == PackageManager.PERMISSION_DENIED)
        return app
    }
}
