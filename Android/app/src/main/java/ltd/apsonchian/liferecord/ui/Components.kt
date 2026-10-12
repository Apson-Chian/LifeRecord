package ltd.apsonchian.liferecord.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*

@Composable fun AppButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,colors:ButtonColors=ButtonDefaults.buttonColors(containerColor=Purple,contentColor=Color.White),shape:Shape=RoundedCornerShape(15.dp),contentPadding:PaddingValues=PaddingValues(horizontal=16.dp,vertical=10.dp),content:@Composable RowScope.()->Unit) {
    StyledButton(onClick,modifier,enabled,colors.containerColor,colors.contentColor,shape,contentPadding,true,content)
}
@Composable fun SoftButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,shape:Shape=RoundedCornerShape(15.dp),contentPadding:PaddingValues=PaddingValues(horizontal=16.dp,vertical=10.dp),content:@Composable RowScope.()->Unit) {
    StyledButton(onClick,modifier,enabled,MaterialTheme.colorScheme.primary,MaterialTheme.colorScheme.primary,shape,contentPadding,false,content)
}
@Composable private fun StyledButton(onClick:()->Unit,modifier:Modifier,enabled:Boolean,tint:Color,foreground:Color,shape:Shape,padding:PaddingValues,prominent:Boolean,content:@Composable RowScope.()->Unit) {
    val source=remember { MutableInteractionSource() };val pressed by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if(pressed) .98f else 1f,spring(dampingRatio=1f,stiffness=850f),label="button press")
    val gradient=if(prominent) listOf(tint,tint.copy(alpha=.85f)) else listOf(tint.copy(alpha=.12f),tint.copy(alpha=.07f))
    Row(modifier.graphicsLayer { scaleX=scale;scaleY=scale;alpha=if(!enabled) .45f else if(pressed) .8f else 1f }
        .clip(shape).background(Brush.linearGradient(gradient)).border(.7.dp,if(prominent) Color.White.copy(alpha=.16f) else tint.copy(alpha=.16f),shape)
        .clickable(enabled=enabled,interactionSource=source,indication=null,role=Role.Button,onClick=onClick)
        .defaultMinSize(minHeight=44.dp).padding(padding),horizontalArrangement=Arrangement.Center,verticalAlignment=Alignment.CenterVertically) {
        CompositionLocalProvider(LocalContentColor provides foreground) { ProvideTextStyle(MaterialTheme.typography.bodyMedium.copy(fontWeight=FontWeight.SemiBold)) { content() } }
    }
}
@Composable fun IconBadge(kind:Glyph,tint:Color,size:Dp=44.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(size*.3f)).background(tint.copy(alpha=if(MaterialTheme.colorScheme.background.luminance()<.2f) .18f else .10f)).border(.7.dp,tint.copy(alpha=.14f),RoundedCornerShape(size*.3f)),contentAlignment=Alignment.Center) {
        AppIcon(kind,tint,Modifier.size(size*.45f))
    }
}
@Composable fun SymbolButton(kind:Glyph,description:String,onClick:()->Unit,modifier:Modifier=Modifier) {
    val color=MaterialTheme.colorScheme.primary
    Box(modifier.size(44.dp).shadow(5.dp,RoundedCornerShape(50),ambientColor=Color.Black.copy(alpha=.04f),spotColor=Color.Black.copy(alpha=.04f))
        .clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.surface.copy(alpha=.85f)).clickable(role=Role.Button,onClick=onClick),contentAlignment=Alignment.Center) {
        if(kind==Glyph.Plus) Box(Modifier.size(34.dp).border(1.dp,color.copy(alpha=.22f),RoundedCornerShape(50)),contentAlignment=Alignment.Center) {AppIcon(kind,color,Modifier.size(25.dp),description)}
        else AppIcon(kind,color,Modifier.size(22.dp),description)
    }
}
