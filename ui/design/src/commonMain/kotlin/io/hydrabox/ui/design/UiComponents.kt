package io.hydrabox.ui.design

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

@Composable
fun UiSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(UiTokens.spacing)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        content()
    }
}

@Composable
fun UiCard(title: String, detail: String? = null, onClick: (() -> Unit)? = null) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick ?: {},
        enabled = onClick != null,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        ListItem(headlineContent = { Text(title) }, supportingContent = detail?.let { { Text(it) } })
    }
}

@Composable
fun UiAction(label: String, enabled: Boolean, secondary: Boolean = false, onClick: () -> Unit) {
    if (secondary) OutlinedButton(onClick = onClick, enabled = enabled) { Text(label) }
    else Button(onClick = onClick, enabled = enabled) { Text(label) }
}

@Composable
fun UiActionRow(primary: String, primaryEnabled: Boolean, secondary: String? = null, onPrimary: () -> Unit, onSecondary: () -> Unit = {}) {
    Row(horizontalArrangement = Arrangement.spacedBy(UiTokens.spacing), modifier = Modifier.padding(vertical = UiTokens.spacing)) {
        UiAction(primary, primaryEnabled, onClick = onPrimary)
        secondary?.let { UiAction(it, true, secondary = true, onClick = onSecondary) }
    }
}
