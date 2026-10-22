package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Match the iOS lightweight heading/list/inline renderer without HTML or web content. */
@Composable fun MarkdownText(content:String, bodyStyle:TextStyle=MaterialTheme.typography.bodyLarge) {
    Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
        content.replace("\r\n","\n").split('\n').forEach { line ->
            val trimmed=line.trim()
            val heading=trimmed.takeWhile { it=='#' }.length.takeIf { it in 1..6 && trimmed.getOrNull(it)==' ' }
            val display=when { heading!=null -> trimmed.drop(heading+1);trimmed.startsWith("- ") || trimmed.startsWith("* ") -> "• "+trimmed.drop(2);else -> line }
            if(display.isBlank()) Spacer(Modifier.height(2.dp)) else if(trimmed=="---" || trimmed=="***") HorizontalDivider() else {
                val style=when(heading) { 1 -> MaterialTheme.typography.headlineSmall;2 -> MaterialTheme.typography.titleLarge;3 -> MaterialTheme.typography.bodyMedium.copy(fontWeight=FontWeight.SemiBold);else -> bodyStyle }
                Text(inlineMarkdown(display),style=style)
            }
        }
    }
}
private fun inlineMarkdown(text:String)=buildAnnotatedString {
    val pattern=Regex("\\*\\*(.+?)\\*\\*|`([^`]+)`")
    var position=0
    pattern.findAll(text).forEach { match ->
        append(text.substring(position,match.range.first))
        val bold=match.groups[1]!=null
        withStyle(if(bold) SpanStyle(fontWeight=FontWeight.SemiBold) else SpanStyle(fontFamily=FontFamily.Monospace)) { append(match.groups[if(bold) 1 else 2]!!.value) }
        position=match.range.last+1
    }
    append(text.substring(position))
}
