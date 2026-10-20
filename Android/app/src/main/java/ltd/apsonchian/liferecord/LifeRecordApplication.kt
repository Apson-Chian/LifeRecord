package ltd.apsonchian.liferecord

import android.app.Application
import ltd.apsonchian.liferecord.data.Store
import ltd.apsonchian.liferecord.data.Secrets
import ltd.apsonchian.liferecord.service.Photos
import ltd.apsonchian.liferecord.service.Network

open class LifeRecordApplication : Application() {
    open val store by lazy { Store(this) }
    open val secrets by lazy { Secrets(this) }
    val photos by lazy { Photos(this) }
    open val network by lazy { Network(baseURL = { store.get("sync.base", Network.BASE) }) }
}
