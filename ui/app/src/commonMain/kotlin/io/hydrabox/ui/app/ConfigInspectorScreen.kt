package io.hydrabox.ui.app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import io.hydrabox.core.projection.MANUAL_SOURCE_ID
import io.hydrabox.core.projection.Notice
import io.hydrabox.core.projection.ScreenState
import io.hydrabox.core.projection.ServerRef
import io.hydrabox.ui.app.resources.*
import io.hydrabox.ui.design.ActionRow
import io.hydrabox.ui.design.ChoiceDialog
import io.hydrabox.ui.design.ConfirmDialog
import io.hydrabox.ui.design.HydraRow
import io.hydrabox.ui.design.OptionRow
import io.hydrabox.ui.design.PrimaryAction
import io.hydrabox.ui.design.SecondaryAction
import io.hydrabox.ui.design.SectionGroup
import io.hydrabox.ui.design.SectionHeader
import io.hydrabox.ui.design.ToggleRow
import io.hydrabox.ui.design.UiTokens
import io.hydrabox.ui.design.WarningStrip
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import org.jetbrains.compose.resources.stringResource

private val jsonFormatter = Json { prettyPrint = true }

internal fun prettyConfigJson(configJson: String): String =
    runCatching {
        jsonFormatter.encodeToString(JsonElement.serializer(), jsonFormatter.parseToJsonElement(configJson))
    }.getOrDefault(configJson)

private fun prettyConfigJson(config: JsonObject): String = jsonFormatter.encodeToString(JsonElement.serializer(), config)

private fun parseConfigObject(configJson: String): JsonObject? =
    runCatching { jsonFormatter.parseToJsonElement(configJson) as? JsonObject }.getOrNull()

@Composable
internal fun ConfigInspectorScreen(
    server: ServerRef,
    state: ScreenState,
    actions: AppActions,
) {
    val originalRaw = remember(server.id, server.configJson) { prettyConfigJson(server.configJson ?: "{}") }
    val originalConfig = remember(server.id, server.configJson) { parseConfigObject(originalRaw) ?: JsonObject(emptyMap()) }
    val initiallyValid = remember(server.id, server.configJson) { parseConfigObject(originalRaw) != null }
    var editedConfig by remember(server.id, server.configJson) { mutableStateOf(originalConfig) }
    var rawDraft by remember(server.id, server.configJson) { mutableStateOf(originalRaw) }
    var rawDraftValid by remember(server.id, server.configJson) { mutableStateOf(initiallyValid) }
    var invalidTypedJsonFields by remember(server.id, server.configJson) { mutableStateOf(emptySet<List<String>>()) }
    var rawMode by remember(server.id, server.configJson) { mutableStateOf(false) }
    var confirmRemoval by remember { mutableStateOf(false) }
    val type = (editedConfig["type"] as? JsonPrimitive)?.contentOrNull ?: server.type
    val busy = state.busy.source
    val changed = editedConfig != originalConfig || (rawMode && rawDraft != originalRaw)
    val typedJsonInvalid =
        invalidTypedJsonFields.any { path ->
            configFieldSections(type).any { section ->
                section.fields.any { it.path == path && it.format == ConfigValueFormat.JSON && configFieldVisible(editedConfig, it) }
            }
        }
    val canSave = changed && !busy && rawDraftValid && !typedJsonInvalid && hasRequiredConfigFields(editedConfig, type)

    Column(
        verticalArrangement = Arrangement.spacedBy(UiTokens.spacing * 2),
        modifier = Modifier.fillMaxWidth().padding(horizontal = UiTokens.spacing * 2),
    ) {
        SectionGroup {
            Column(
                verticalArrangement = Arrangement.spacedBy(UiTokens.spacing / 2),
                modifier = Modifier.padding(UiTokens.spacing * 2),
            ) {
                Text(server.displayName, style = MaterialTheme.typography.titleLarge)
                if (server.id != server.displayName) {
                    Text(server.id, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(
                    stringResource(Res.string.config_protocol, type ?: stringResource(Res.string.config_protocol_unknown)),
                    style = MaterialTheme.typography.bodyMedium,
                )
                ConfigFlags(server)
            }
        }

        state.notice
            ?.takeIf { it == Notice.CONFIG_UPDATE_FAILED || it == Notice.CONFIG_REMOVE_FAILED }
            ?.let { WarningStrip(text = noticeText(it, state.sourceOperationError)) }
        if (server.sourceId != MANUAL_SOURCE_ID) {
            SectionGroup {
                Text(
                    stringResource(Res.string.config_subscription_edit_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(UiTokens.spacing * 2),
                )
            }
        }

        ActionRow {
            SecondaryAction(
                label = stringResource(if (rawMode) Res.string.config_form_typed else Res.string.config_form_advanced_json),
                enabled = !busy && (!rawMode || rawDraftValid) && (rawMode || !typedJsonInvalid),
                onClick = {
                    if (rawMode) {
                        parseConfigObject(rawDraft)?.let { parsed ->
                            editedConfig = parsed
                            rawDraft = prettyConfigJson(parsed)
                            rawMode = false
                        }
                    } else {
                        rawDraft = prettyConfigJson(editedConfig)
                        rawDraftValid = true
                        rawMode = true
                    }
                },
            )
        }

        if (rawMode) {
            SectionGroup(title = stringResource(Res.string.config_raw_json)) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(UiTokens.spacing),
                    modifier = Modifier.padding(UiTokens.spacing * 2),
                ) {
                    OutlinedTextField(
                        value = rawDraft,
                        enabled = !busy,
                        onValueChange = { value ->
                            rawDraft = value
                            val parsed = parseConfigObject(value)
                            rawDraftValid = parsed != null
                            if (parsed != null) editedConfig = parsed
                        },
                        label = { Text(stringResource(Res.string.config_json_field)) },
                        singleLine = false,
                        minLines = 12,
                        maxLines = 24,
                        textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        shape = MaterialTheme.shapes.medium,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (!rawDraftValid) WarningStrip(text = stringResource(Res.string.config_json_invalid))
                }
            }
        } else {
            ConfigParametersSection(
                config = editedConfig,
                type = type,
                enabled = !busy,
                onChange = { field, value ->
                    val updated = updateConfigField(editedConfig, field, value)
                    editedConfig = updated
                    val visibleJsonPaths =
                        configFieldSections(type)
                            .flatMap { it.fields }
                            .filter { it.format == ConfigValueFormat.JSON && configFieldVisible(updated, it) }
                            .map(ConfigFieldDescriptor::path)
                            .toSet()
                    invalidTypedJsonFields = invalidTypedJsonFields.intersect(visibleJsonPaths)
                    rawDraft = prettyConfigJson(updated)
                    rawDraftValid = true
                },
                onJsonValidityChange = { path, valid ->
                    invalidTypedJsonFields =
                        invalidTypedJsonFields.toMutableSet().apply {
                            if (valid) remove(path) else add(path)
                        }
                },
            )
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        ActionRow {
            PrimaryAction(
                label = stringResource(Res.string.action_save),
                enabled = canSave,
                onClick = { actions.onUpdateConfig(server.id, if (rawMode) rawDraft else prettyConfigJson(editedConfig)) },
            )
            if (changed) {
                SecondaryAction(
                    label = stringResource(Res.string.config_reset),
                    enabled = !busy,
                    onClick = {
                        editedConfig = originalConfig
                        rawDraft = originalRaw
                        rawDraftValid = initiallyValid
                        invalidTypedJsonFields = emptySet()
                    },
                )
            }
        }

        ActionRow {
            TextButton(
                enabled = !busy,
                onClick = { confirmRemoval = true },
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) { Text(stringResource(Res.string.action_remove)) }
        }
    }
    if (confirmRemoval) {
        ConfirmDialog(
            title = stringResource(Res.string.config_remove_title),
            body = stringResource(Res.string.config_remove_body),
            confirmLabel = stringResource(Res.string.action_remove),
            dismissLabel = stringResource(Res.string.action_cancel),
            destructive = true,
            onConfirm = {
                confirmRemoval = false
                actions.onRemoveConfig(server.id)
            },
            onDismiss = { confirmRemoval = false },
        )
    }
}

@Composable
private fun ConfigFlags(server: ServerRef) {
    Text(
        listOf(
            stringResource(if (server.endpoint) Res.string.config_kind_endpoint else Res.string.config_kind_outbound),
            stringResource(if (server.selectable) Res.string.config_selectable else Res.string.config_not_selectable),
        ).joinToString(" · "),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun ConfigParametersSection(
    config: JsonObject,
    type: String?,
    enabled: Boolean,
    onChange: (ConfigFieldDescriptor, String) -> Unit,
    onJsonValidityChange: (List<String>, Boolean) -> Unit,
) {
    SectionHeader(stringResource(Res.string.config_parameters))
    configFieldSections(type).forEach { section ->
        val fields = section.fields.filter { configFieldVisible(config, it) }
        if (fields.isNotEmpty()) {
            SectionGroup(title = stringResource(section.title)) {
                fields.forEachIndexed { index, field ->
                    ConfigFieldEditor(config, field, enabled, onChange, onJsonValidityChange)
                    if (index < fields.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(horizontal = UiTokens.spacing * 2),
                            color = MaterialTheme.colorScheme.outlineVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ConfigFieldEditor(
    config: JsonObject,
    field: ConfigFieldDescriptor,
    enabled: Boolean,
    onChange: (ConfigFieldDescriptor, String) -> Unit,
    onJsonValidityChange: (List<String>, Boolean) -> Unit,
) {
    val label = field.label?.let { stringResource(it) } ?: field.path.last().replace('_', ' ')
    val value = configFieldValue(config, field)
    val requiredHint = if (field.required) stringResource(Res.string.config_field_required) else null
    val fieldDefault = configFieldDefaultValue(config, field)
    val defaultHint = fieldDefault?.let { stringResource(Res.string.config_field_default, it) }
    val supporting = listOfNotNull(requiredHint, defaultHint).joinToString(" · ").ifEmpty { null }
    when (field.kind) {
        ConfigFieldKind.TEXT, ConfigFieldKind.NUMBER -> {
            var jsonDraft by remember(field.path, value) { mutableStateOf(value) }
            var jsonDraftValid by remember(field.path, value) { mutableStateOf(true) }
            val jsonField = field.format == ConfigValueFormat.JSON
            OutlinedTextField(
                value = if (jsonField) jsonDraft else value,
                onValueChange = { input ->
                    if (jsonField) {
                        jsonDraft = input
                        val valid = input.isBlank() || runCatching { Json.parseToJsonElement(input) }.isSuccess
                        jsonDraftValid = valid
                        onJsonValidityChange(field.path, valid)
                        if (valid) onChange(field, input)
                    } else {
                        val normalized =
                            if (field.kind == ConfigFieldKind.NUMBER && field.format == ConfigValueFormat.NUMBER) {
                                input.filter(Char::isDigit)
                            } else {
                                input
                            }
                        onChange(field, normalized)
                    }
                },
                enabled = enabled,
                label = { Text(label) },
                isError = jsonField && !jsonDraftValid,
                supportingText =
                    if (jsonField && !jsonDraftValid) {
                        { Text(stringResource(Res.string.config_field_json_invalid)) }
                    } else {
                        supporting?.let { { Text(it) } }
                    },
                placeholder = fieldDefault?.let { hint -> { Text(hint) } },
                singleLine = !jsonField,
                minLines = if (jsonField) 3 else 1,
                maxLines = if (jsonField) 8 else 1,
                keyboardOptions =
                    KeyboardOptions(
                        keyboardType =
                            if (field.kind == ConfigFieldKind.NUMBER && field.format == ConfigValueFormat.NUMBER) {
                                KeyboardType.Number
                            } else {
                                KeyboardType.Text
                            },
                    ),
                shape = MaterialTheme.shapes.medium,
                modifier = Modifier.fillMaxWidth().padding(horizontal = UiTokens.spacing * 2, vertical = UiTokens.spacing),
            )
        }

        ConfigFieldKind.BOOLEAN -> {
            ToggleRow(
                title = label,
                supporting = supporting,
                checked = value.toBooleanStrictOrNull() ?: false,
                enabled = enabled,
                onCheckedChange = { onChange(field, it.toString()) },
            )
        }

        ConfigFieldKind.CHOICE -> {
            var choosing by remember(field.path) { mutableStateOf(false) }
            val selectedValue = value.ifEmpty { fieldDefault.orEmpty() }
            val choices = configFieldChoices(config, field)
            HydraRow(
                title = label,
                supporting = value.ifEmpty { defaultHint ?: stringResource(Res.string.config_transport_none) },
                onClick =
                    if (enabled) {
                        { choosing = true }
                    } else {
                        null
                    },
            )
            if (choosing) {
                ChoiceDialog(
                    title = label,
                    dismissLabel = stringResource(Res.string.action_cancel),
                    onDismiss = { choosing = false },
                ) {
                    val options =
                        (
                            (if (field.required) emptyList() else listOf("")) + choices +
                                listOfNotNull(selectedValue.takeIf { it.isNotEmpty() && it !in choices })
                        ).distinct()
                    options.forEach { option ->
                        OptionRow(
                            title = option.ifEmpty { stringResource(Res.string.config_transport_none) },
                            supporting = null,
                            selected = option == selectedValue,
                            onClick = {
                                onChange(field, option)
                                choosing = false
                            },
                        )
                    }
                }
            }
        }

        ConfigFieldKind.MULTI_CHOICE -> {
            var choosing by remember(field.path) { mutableStateOf(false) }
            val selectedValues = (value.ifEmpty { fieldDefault.orEmpty() }).split(',').map(String::trim).filter(String::isNotEmpty)
            HydraRow(
                title = label,
                supporting = value.ifEmpty { defaultHint ?: stringResource(Res.string.config_transport_none) },
                onClick =
                    if (enabled) {
                        { choosing = true }
                    } else {
                        null
                    },
            )
            if (choosing) {
                ChoiceDialog(
                    title = label,
                    dismissLabel = stringResource(Res.string.action_close),
                    onDismiss = { choosing = false },
                ) {
                    val choices = configFieldChoices(config, field)
                    (choices + selectedValues.filterNot(choices::contains)).forEach { option ->
                        val selected = option in selectedValues
                        Row(
                            modifier =
                                Modifier
                                    .fillMaxWidth()
                                    .clickable(enabled = enabled) {
                                        val updated = if (selected) selectedValues - option else selectedValues + option
                                        onChange(field, updated.joinToString(","))
                                    }.padding(horizontal = UiTokens.spacing * 2),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(checked = selected, onCheckedChange = null, enabled = enabled)
                            Text(option, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
        }
    }
}
