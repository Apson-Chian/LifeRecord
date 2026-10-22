package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.*
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.unit.*
import androidx.compose.ui.semantics.*
import kotlinx.coroutines.launch

// Cards sample only the ambient backdrop; floating chrome samples page content.
// Keeping these sources separate prevents recursive glass or blurred labels.
internal val LocalGlassAmbient=staticCompositionLocalOf<GlassBackdrop?> {null}
internal val LocalGlassPage=staticCompositionLocalOf<GlassBackdrop?> {null}
internal enum class GlassKind {Card,Floating,Sheet,Dialog,Control}

@Composable
internal fun Modifier.liquidMaterial(
    backdrop:GlassBackdrop?,kind:GlassKind=GlassKind.Card,radius:Dp=26.dp,
    tint:Color=MaterialTheme.colorScheme.primary,
    blurEnabled:Boolean=rememberBackdropBlurEnabled(),
):Modifier {
    val enabled=blurEnabled && android.os.Build.VERSION.SDK_INT>=31
    val dark=MaterialTheme.colorScheme.background.luminance()<.2f
    val capsule=kind==GlassKind.Floating
    val topOnly=kind==GlassKind.Sheet
    val shape=when {capsule->RoundedCornerShape(50);topOnly->RoundedCornerShape(topStart=radius,topEnd=radius);else->RoundedCornerShape(radius)}
    val elevation=when(kind) {GlassKind.Card->14.dp;GlassKind.Floating->22.dp;GlassKind.Sheet->28.dp;GlassKind.Dialog->28.dp;GlassKind.Control->2.dp}
    var result=this.shadow(elevation,shape,clip=false,ambientColor=Color.Black.copy(alpha=if(dark) .22f else .045f),spotColor=Color.Black.copy(alpha=if(dark) .26f else .095f))
        .shadow(1.dp,shape,clip=false,ambientColor=Color.Black.copy(alpha=.045f),spotColor=Color.Black.copy(alpha=.10f)).clip(shape)
    if(enabled && backdrop!=null) {
        val blur=when(kind) {GlassKind.Card->4.dp;GlassKind.Floating->8.dp;GlassKind.Sheet->16.dp;GlassKind.Dialog->14.dp;GlassKind.Control->2.dp}
        val depth=when(kind) {GlassKind.Floating->12.dp;GlassKind.Sheet,GlassKind.Dialog->9.dp;GlassKind.Control->3.dp;else->6.dp}
        result=result.liquidBackdrop(backdrop,radius,blur,depth,if(kind==GlassKind.Control) 8.dp else 18.dp,capsule,topOnly)
    }
    return result.liquidFinish(kind,shape,tint,dark,opaque=!enabled || backdrop==null && kind!=GlassKind.Control)
}

/** A single light direction, a soft transmission wash and a fine inner bevel.
 * Broad glints stay behind content; the only foreground paint is the thin rim.
 */
@Composable
internal fun Modifier.liquidFinish(kind:GlassKind,shape:Shape,tint:Color,dark:Boolean,opaque:Boolean=false):Modifier {
    val surface=MaterialTheme.colorScheme.surface
    val fill=if(opaque) .97f else when(kind) {
        GlassKind.Card->if(dark) .48f else .50f
        GlassKind.Floating->if(dark) .34f else .22f
        GlassKind.Sheet,GlassKind.Dialog->if(dark) .80f else .78f
        GlassKind.Control->if(dark) .35f else .45f
    }
    return drawWithCache {
        val outline=shape.createOutline(size,layoutDirection,this)
        val wash=Brush.linearGradient(listOf(Color.White.copy(alpha=if(dark) .065f else .20f),Color.White.copy(alpha=if(dark) .015f else .025f),tint.copy(alpha=if(dark) .035f else .012f)),Offset.Zero,Offset(size.width,size.height))
        val glint=Brush.radialGradient(listOf(Color.White.copy(alpha=if(dark) .07f else .16f),Color.Transparent),Offset(size.width*.12f,-size.height*.25f),(size.maxDimension*.85f).coerceAtLeast(1f))
        val rim=Brush.linearGradient(0f to Color.White.copy(alpha=if(dark) .36f else .92f),.30f to Color.White.copy(alpha=if(dark) .10f else .30f),.55f to Color.White.copy(alpha=.015f),.76f to Color.Black.copy(alpha=if(dark) .18f else .055f),1f to Color.White.copy(alpha=if(dark) .22f else .65f),start=Offset.Zero,end=Offset(size.width,size.height))
        onDrawWithContent {
            drawOutline(outline,surface.copy(alpha=fill))
            drawOutline(outline,wash);drawOutline(outline,glint)
            drawContent()
            drawOutline(outline,rim,style=Stroke(1.25.dp.toPx()))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun GlassBottomSheet(
    onDismissRequest:()->Unit,modifier:Modifier=Modifier,
    sheetState:SheetState=rememberModalBottomSheetState(),
    content:@Composable ColumnScope.()->Unit,
) {
    val scope=rememberCoroutineScope()
    fun toggle() {scope.launch {
        if(sheetState.currentValue==SheetValue.PartiallyExpanded) sheetState.expand()
        else if(sheetState.hasPartiallyExpandedState) sheetState.partialExpand()
    }}
    ModalBottomSheet(onDismissRequest=onDismissRequest,sheetState=sheetState,
        modifier=modifier,dragHandle=null,
        shape=RoundedCornerShape(topStart=32.dp,topEnd=32.dp),containerColor=Color.Transparent,tonalElevation=0.dp) {
        // Material must live inside the sheet's moving Surface. An outer clip
        // precedes Material3's offset and clips partially expanded content away.
        Column(Modifier.fillMaxWidth().liquidMaterial(LocalGlassPage.current,GlassKind.Sheet,32.dp)) {
            Box(Modifier.align(Alignment.CenterHorizontally).clickable(onClick=::toggle).semantics(mergeDescendants=true) {
                contentDescription="调整面板高度"
                dismiss("关闭面板") {onDismissRequest();true}
                if(sheetState.currentValue==SheetValue.PartiallyExpanded) expand("展开面板") {toggle();true}
                else if(sheetState.hasPartiallyExpandedState) collapse("收起面板") {toggle();true}
            }) {BottomSheetDefaults.DragHandle()}
            content()
        }
    }
}

@Composable internal fun GlassAlertDialog(
    onDismissRequest:()->Unit,confirmButton:@Composable ()->Unit,modifier:Modifier=Modifier,
    dismissButton:(@Composable ()->Unit)?=null,title:(@Composable ()->Unit)?=null,text:(@Composable ()->Unit)?=null,
) {
    AlertDialog(onDismissRequest=onDismissRequest,confirmButton=confirmButton,dismissButton=dismissButton,title=title,text=text,
        modifier=modifier.liquidMaterial(LocalGlassPage.current,GlassKind.Dialog,28.dp),shape=RoundedCornerShape(28.dp),containerColor=Color.Transparent,tonalElevation=0.dp)
}
