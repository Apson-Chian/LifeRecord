package ltd.apsonchian.liferecord

import android.app.Application
import ltd.apsonchian.liferecord.data.Store
import ltd.apsonchian.liferecord.data.Secrets
import ltd.apsonchian.liferecord.service.Photos
import ltd.apsonchian.liferecord.service.Network

class LifeRecordApplication : Application() {
    val store by lazy { Store(this) }
    val secrets by lazy { Secrets(this) }
    val photos by lazy { Photos(this) }
    val network by lazy { Network(baseURL = { store.get("sync.base", Network.BASE) }) }
}
