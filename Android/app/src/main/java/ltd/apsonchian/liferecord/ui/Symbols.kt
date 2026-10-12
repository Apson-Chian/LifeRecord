package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.semantics.*
import kotlin.math.*

enum class Glyph { Home,Trend,Coach,Settings,Meal,Weight,Workout,Person,Target,Sync,Bell,Shield,Calendar,Sidebar,Compose,Plus,Chevron,Lightbulb,Photo,Archive,Up,List,Figure,Percent }
/** Shared optical weight and proportions; all paths are drawn locally. */
@Composable fun AppIcon(kind:Glyph,color:Color,modifier:Modifier=Modifier,description:String?=null,filled:Boolean=false) {
    Canvas(if(description==null) modifier else modifier.semantics { contentDescription=description }) {
        scale(size.width/24f,size.height/24f,pivot=Offset.Zero) {
            val stroke=Stroke(1.65f,cap=StrokeCap.Round,join=StrokeJoin.Round)
            fun line(x:Float,y:Float,xx:Float,yy:Float,w:Float=1.65f) { drawLine(color,Offset(x,y),Offset(xx,yy),w,StrokeCap.Round) }
            fun path(vararg points:Float):Path=Path().apply { moveTo(points[0],points[1]);for(i in 2 until points.size step 2) lineTo(points[i],points[i+1]) }
            fun outline(p:Path)=drawPath(p,color,style=stroke)
            fun box(x:Float,y:Float,w:Float,h:Float,r:Float=3f) { drawRoundRect(color,Offset(x,y),Size(w,h),CornerRadius(r),style=stroke) }
            when(kind) {
                Glyph.Plus -> { line(5f,12f,19f,12f);line(12f,5f,12f,19f) }
                Glyph.Up -> { line(12f,19f,12f,5f,2.2f);outline(path(6f,11f,12f,5f,18f,11f)) }
                Glyph.Chevron -> outline(path(9f,5f,16f,12f,9f,19f))
                Glyph.Home -> {
                    val p=path(4f,10f,12f,3.2f,20f,10f,20f,21f,14.3f,21f,14.3f,14.5f,9.7f,14.5f,9.7f,21f,4f,21f).apply {close()}
                    if(filled) drawPath(p,color) else outline(p)
                    outline(path(1.5f,10.5f,12f,1.5f,22.5f,10.5f))
                }
                Glyph.Trend -> { line(3f,3f,3f,21f,2f);line(3f,21f,22f,21f,2f);outline(path(5.5f,15f,10.5f,10f,15f,13f,21f,6f));outline(path(17f,6f,21f,6f,21f,10f)) }
                Glyph.Coach -> {
                    val back=path(3f,3f,16f,3f).apply {quadraticTo(19f,3f,19f,6f);lineTo(19f,12f);quadraticTo(19f,15f,16f,15f);lineTo(7f,15f);lineTo(3f,18f);lineTo(3f,15f);quadraticTo(1f,15f,1f,12f);lineTo(1f,6f);quadraticTo(1f,3f,3f,3f);close()}
                    if(!filled) outline(back)
                    val front=path(9f,10f,21f,10f).apply {quadraticTo(23f,10f,23f,13f);lineTo(23f,19f);quadraticTo(23f,21f,21f,21f);lineTo(21f,23f);lineTo(17f,21f);lineTo(9f,21f);quadraticTo(7f,21f,7f,19f);lineTo(7f,13f);quadraticTo(7f,10f,9f,10f);close()}
                    if(filled) {
                        val halo=Path().apply {addRoundRect(RoundRect(Rect(5.5f,8.5f,24.5f,23f),CornerRadius(3f)))}
                        drawPath(Path.combine(PathOperation.Difference,back,halo),color)
                        drawPath(front,color)
                    } else outline(front)
                }
                Glyph.Settings -> {
                    val p=Path().apply {
                        repeat(8) { tooth ->
                            for((offset,r) in listOf(-.34 to 8.0,-.24 to 10.5,.24 to 10.5,.34 to 8.0)) {
                                val a=tooth*PI/4+offset;val x=12+r*cos(a);val y=12+r*sin(a)
                                if(tooth==0 && offset==-.34) moveTo(x.toFloat(),y.toFloat()) else lineTo(x.toFloat(),y.toFloat())
                            }
                        };close();addOval(Rect(8.6f,8.6f,15.4f,15.4f));fillType=PathFillType.EvenOdd
                    }
                    if(filled) drawPath(p,color) else drawPath(p,color,style=Stroke(1.3f,join=StrokeJoin.Round))
                }
                Glyph.Meal -> {
                    outline(Path().apply {moveTo(3f,2f);lineTo(3f,7f);quadraticTo(3f,10f,7f,10f);quadraticTo(11f,10f,11f,7f);lineTo(11f,2f)})
                    line(7f,2f,7f,22f,2.5f)
                    drawPath(Path().apply {moveTo(20f,2f);quadraticTo(14f,5f,15f,13f);lineTo(18f,13f);lineTo(18f,22f);lineTo(20f,22f);close()},color)
                }
                Glyph.Weight -> { drawCircle(color,2f,Offset(12f,4.5f),style=stroke);outline(path(5f,9f,19f,9f,22f,22f,2f,22f,5f,9f)) }
                Glyph.Workout -> {box(1f,8f,3f,8f,1f);box(4f,5f,4f,14f,1.3f);line(8f,10f,16f,10f);line(8f,14f,16f,14f);box(16f,5f,4f,14f,1.3f);box(20f,8f,3f,8f,1f)}
                Glyph.Person -> {drawCircle(color,3.5f,Offset(12f,6f),style=stroke);outline(Path().apply {moveTo(3f,21f);cubicTo(3f,11f,21f,11f,21f,21f);close()})}
                Glyph.Target -> {for(r in listOf(10f,6f,2f)) drawCircle(color,r,Offset(12f,12f),style=stroke)}
                Glyph.Sync -> {drawArc(color,205f,145f,false,Offset(4f,4f),Size(16f,16f),style=stroke);drawArc(color,25f,145f,false,Offset(4f,4f),Size(16f,16f),style=stroke);outline(path(16f,7f,20f,10f,22f,6f));outline(path(2f,18f,4f,14f,8f,17f))}
                Glyph.Bell -> {outline(Path().apply {moveTo(4f,18f);lineTo(6f,15f);lineTo(6f,9f);cubicTo(6f,1f,18f,1f,18f,9f);lineTo(18f,15f);lineTo(20f,18f);close()});drawArc(color,0f,180f,false,Offset(9f,18f),Size(6f,5f),style=stroke)}
                Glyph.Shield -> {outline(Path().apply {moveTo(3f,5f);lineTo(12f,2f);lineTo(21f,5f);lineTo(21f,12f);quadraticTo(20f,19f,12f,23f);quadraticTo(4f,19f,3f,12f);close()});outline(path(7f,12f,10.5f,15.5f,17f,9f))}
                Glyph.Calendar -> {box(2f,4f,20f,18f,3f);line(2f,9f,22f,9f);line(7f,2f,7f,6f);line(17f,2f,17f,6f);for(y in listOf(12f,16f,19f)) for(x in listOf(6f,10f,14f,18f)) drawCircle(color,.75f,Offset(x,y))}
                Glyph.Sidebar -> {box(1.5f,3f,21f,18f);line(8f,3f,8f,21f);for(y in listOf(7f,11f,15f)) line(4f,y,5.5f,y,1f)}
                Glyph.Compose -> {outline(Path().apply {moveTo(12f,4f);lineTo(5f,4f);quadraticTo(2f,4f,2f,7f);lineTo(2f,19f);quadraticTo(2f,22f,5f,22f);lineTo(18f,22f);quadraticTo(21f,22f,21f,19f);lineTo(21f,12f)});outline(path(9f,16f,10f,12f,20f,2f,23f,5f,13f,15f,9f,16f))}
                Glyph.Photo -> {box(1f,5f,18f,17f);drawCircle(color,1.5f,Offset(6f,10f),style=stroke);outline(path(2f,18f,8f,13f,12f,16f,16f,11f,19f,14f));outline(path(6f,2f,23f,2f,23f,17f))}
                Glyph.Archive -> {box(3f,7f,18f,15f,2f);line(5f,4f,19f,4f);line(7f,1f,17f,1f);outline(path(12f,10f,12f,18f));line(8f,14f,16f,14f)}
                Glyph.List -> {box(1f,3f,22f,18f,2f);for(y in listOf(7f,12f,17f)) {drawCircle(color,.7f,Offset(5f,y));line(8f,y,19f,y,1.2f)}}
                Glyph.Lightbulb -> {outline(Path().apply {moveTo(8f,17f);cubicTo(8f,12f,5f,12f,5f,7f);cubicTo(5f,-1f,19f,-1f,19f,7f);cubicTo(19f,12f,16f,12f,16f,17f);close()});line(9f,20f,15f,20f);line(10f,23f,14f,23f)}
                Glyph.Percent -> {drawCircle(color,3.4f,Offset(6f,6f),style=stroke);drawCircle(color,3.4f,Offset(18f,18f),style=stroke);line(4f,21f,20f,3f)}
                Glyph.Figure -> {drawCircle(color,2.3f,Offset(12f,3f));line(12f,7f,12f,14f,2f);line(12f,8f,5f,11f,2f);line(12f,8f,19f,11f,2f);line(12f,14f,8f,22f,2f);line(12f,14f,16f,22f,2f)}
            }
        }
    }
}
