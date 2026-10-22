package ltd.apsonchian.liferecord.ui

import android.graphics.RenderEffect as NativeEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.*
import kotlin.math.ceil
import kotlin.math.min

internal enum class LiquidOptics { Auto, Compatible }

/** Draw only the captured background. Foreground glyphs never enter this filter.
 * Screen coordinates also align material in a Dialog window with its activity.
 */
@Composable
internal fun Modifier.liquidBackdrop(
    backdrop: GlassBackdrop,
    corner: Dp,
    blur: Dp,
    depth: Dp,
    bevel: Dp,
    capsule: Boolean = false,
    topOnly: Boolean = false,
    optics: LiquidOptics = LiquidOptics.Auto,
): Modifier {
    var origin by remember {mutableStateOf(Offset.Zero)}
    var dimensions by remember {mutableStateOf(IntSize.Zero)}
    val inputScale=.5f
    val density=LocalDensity.current.density
    val targetView=LocalView.current
    val crossWindow=backdrop.ownerView?.rootView?.let {it!==targetView.rootView} ?: false
    val layer=rememberGraphicsLayer()
    val background=androidx.compose.material3.MaterialTheme.colorScheme.background
    val padding=ceil((blur.value*3+depth.value+2)*density*inputScale).toInt()
    val effect=remember(dimensions,density,corner,blur,depth,bevel,capsule,topOnly,optics) {
        if(Build.VERSION.SDK_INT>=31 && dimensions.width>0 && dimensions.height>0) {
            val size=Size(dimensions.width*inputScale,dimensions.height*inputScale)
            val radius=if(capsule) size.minDimension/2 else min(corner.value*density*inputScale,size.minDimension/2)
            liquidEffect(size,padding.toFloat(),radius,blur.value*density*inputScale,
                depth.value*density*inputScale,bevel.value*density*inputScale,topOnly,optics)
        } else null
    }
    return onGloballyPositioned {origin=it.positionOnScreen();dimensions=it.size}
        .crossWindowBackdropRedraw(backdrop.ownerView,targetView).legacyBlurRedraw(force=crossWindow).drawWithCache {
            val radius=if(capsule) size.minDimension/2 else min(corner.toPx(),size.minDimension/2)
            fun mask(inset:Float)=Path().apply {
                val r=(radius-inset).coerceAtLeast(0f)
                val bottom=if(topOnly) 0f else r
                addRoundRect(RoundRect(Rect(inset,inset,(size.width-inset).coerceAtLeast(inset),(size.height-inset).coerceAtLeast(inset)),
                    CornerRadius(r),CornerRadius(r),CornerRadius(bottom),CornerRadius(bottom)))
            }
            val bandWidth=min(bevel.toPx(),size.minDimension*.45f)
            val rings=(0..4).map {mask(bandWidth*it/4)}
            onDrawWithContent {
                if(effect!=null && Build.VERSION.SDK_INT>=31 && size.width>0 && size.height>0) {
                    layer.clip=true
                    // The API31 input cache must be invalidated along with its source.
                    layer.renderEffect=if(Build.VERSION.SDK_INT==31 || crossWindow) effect.refresh() else effect.effect
                    layer.record(size=IntSize(ceil(dimensions.width*inputScale).toInt()+padding*2,ceil(dimensions.height*inputScale).toInt()+padding*2)) {
                        drawRect(background)
                        val offset=origin-backdrop.screenOrigin
                        scale(inputScale,inputScale,pivot=Offset.Zero) {
                            translate(padding/inputScale-offset.x,padding/inputScale-offset.y) {drawLayer(backdrop.layer)}
                        }
                    }
                    fun DrawScope.filtered() {
                        scale(1/inputScale,1/inputScale,pivot=Offset.Zero) {
                            translate(-padding.toFloat(),-padding.toFloat()) {drawLayer(layer)}
                        }
                    }
                    filtered()
                    // Android12 has no programmable RuntimeShader. Reuse one blurred
                    // texture through nested lens bands instead of allocating bitmaps.
                    if(!effect.refracted && depth>0.dp) {
                        repeat(4) {index ->
                            val fraction=1-(index+.5f)/4
                            val displacement=depth.toPx()*fraction*fraction
                            clipPath(rings[index]) {clipPath(rings[index+1],ClipOp.Difference) {
                                scale(1+2*displacement/size.width,1+2*displacement/size.height,pivot=center) {filtered()}
                            }}
                        }
                    }
                }
                drawContent()
            }
        }
}

internal data class LiquidEffect(val effect:RenderEffect,val refracted:Boolean,val refresh:()->RenderEffect)

@RequiresApi(31)
internal fun liquidEffect(size:Size,padding:Float,corner:Float,blur:Float,depth:Float,bevel:Float,topOnly:Boolean,optics:LiquidOptics):LiquidEffect {
    val base={if(blur>0) NativeEffect.createBlurEffect(blur,blur,Shader.TileMode.CLAMP) else NativeEffect.createOffsetEffect(0f,0f)}
    if(Build.VERSION.SDK_INT>=33 && optics==LiquidOptics.Auto && depth>0) {
        // Driver/compiler failures retain the same native lens-band path as API31.
        val refracted=runCatching {RefractionShader.effect(size,padding,corner,depth,bevel,topOnly,base)}.getOrNull()
        if(refracted!=null) return refracted
    }
    val refresh={base().asComposeRenderEffect()}
    return LiquidEffect(refresh(),false,refresh)
}

@RequiresApi(33)
private object RefractionShader {
    // Signed rounded-rectangle distance supplies an outward normal. Bend only
    // the bevel: the core remains stable, so background movement does not swim.
    private const val program="""
        uniform shader scene;
        uniform float2 extent;
        uniform float padding;
        uniform float corner;
        uniform float depth;
        uniform float bevel;
        uniform float topOnly;
        half4 main(float2 p) {
            float2 q=p-float2(padding)-extent*.5;
            float r=(topOnly>.5 && q.y>0.0) ? 0.0 : corner;
            float2 k=abs(q)-extent*.5+r;
            float2 outer=max(k,float2(0.0));
            float d=min(max(k.x,k.y),0.0)+length(outer)-r;
            float2 normal;
            if(length(outer)>.001) normal=normalize(outer)*sign(q);
            else normal=k.x>k.y ? float2(sign(q.x),0.0) : float2(0.0,sign(q.y));
            float edge=1.0-smoothstep(0.0,max(bevel,1.0),max(-d,0.0));
            return scene.eval(p-normal*(depth*edge*edge));
        }
    """
    fun effect(size:Size,padding:Float,corner:Float,depth:Float,bevel:Float,topOnly:Boolean,base:()->NativeEffect):LiquidEffect {
        val shader=RuntimeShader(program)
        shader.setFloatUniform("extent",size.width,size.height)
        shader.setFloatUniform("padding",padding);shader.setFloatUniform("corner",corner)
        shader.setFloatUniform("depth",depth);shader.setFloatUniform("bevel",bevel)
        shader.setFloatUniform("topOnly",if(topOnly) 1f else 0f)
        // Refresh the native input binding across window renderers without
        // recompiling the shader or changing any of its uniforms.
        val refresh={NativeEffect.createChainEffect(NativeEffect.createRuntimeShaderEffect(shader,"scene"),base()).asComposeRenderEffect()}
        return LiquidEffect(refresh(),true,refresh)
    }
}
