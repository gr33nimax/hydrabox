package io.hydrabox.ui.app

import java.io.File
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class RussianCopyTest {
    private val russian = File("src/commonMain/composeResources/values-ru/strings.xml").readText()

    @Test fun `russian copy uses one neutral vocabulary`() {
        mapOf(
            "home_empty_title" to "Нет подписки",
            "home_row_exit" to "Внешний IP",
            "home_row_plan" to "Лимит",
            "server_auto" to "Автовыбор",
            "servers_measure" to "Измерить задержку",
            "settings_mode_proxy" to "Прокси",
            "apps_mode_bypass" to "Выбранные приложения — напрямую",
            "traffic_unavailable" to "Статистика появится после начала передачи данных.",
            "settings_proxy_lan" to "Доступ к прокси из локальной сети",
            "settings_support" to "Информация и диагностика",
        ).forEach { (name, value) ->
            assertContains(russian, "<string name=\"$name\">$value</string>")
        }
    }

    @Test fun `smart import has neutral localized copy and error messages`() {
        assertContains(russian, "<string name=\"sources_add_title\">Добавить источник</string>")
        assertContains(russian, "<string name=\"sources_add_field\">Ссылка, подписка или JSON</string>")
        assertContains(russian, "<string name=\"sources_add_hint\">Вставьте ссылку на подписку, один конфиг или список ссылок.</string>")
        assertContains(russian, "<string name=\"servers_manual_group\">Свои конфиги</string>")
        assertContains(russian, "<string name=\"notice_config_import_added\">Конфигурация добавлена</string>")
        assertContains(russian, "<string name=\"notice_config_import_failed\">Не удалось добавить конфигурацию</string>")
        assertContains(russian, "<string name=\"notice_config_import_failed_detail\">Не удалось добавить конфигурацию: %1\$s</string>")
    }

    @Test fun `config inspector copy is localized`() {
        mapOf(
            "config_inspector_title" to "Конфигурация",
            "config_protocol" to "Протокол: %1\$s",
            "config_parameters" to "Параметры",
            "config_section_basic" to "Основное",
            "config_section_tls" to "TLS",
            "config_section_transport" to "Транспорт",
            "config_section_protocol" to "Протокол",
            "config_parameter_server" to "Адрес сервера",
            "config_parameter_port" to "Порт",
            "config_parameter_tls" to "TLS включён",
            "config_parameter_sni" to "Имя сервера (SNI)",
            "config_parameter_transport" to "Тип транспорта",
            "config_parameter_uuid" to "UUID",
            "config_parameter_password" to "Пароль",
            "config_parameter_method" to "Метод шифрования",
            "config_parameter_flow" to "Flow",
            "config_parameter_alpn" to "ALPN",
            "config_parameter_hop_interval" to "Интервал смены порта",
            "config_parameter_network" to "Сетевые протоколы",
            "config_parameter_fingerprint" to "Отпечаток",
            "config_field_required" to "Обязательное поле",
            "config_form_advanced_json" to "Редактировать сырой JSON",
            "config_form_typed" to "Редактировать поля",
            "config_json_invalid" to "Перед сохранением или возвратом к полям JSON должен быть корректным объектом исходящего подключения.",
            "config_raw_json" to "Сырой JSON",
            "config_subscription_edit_hint" to
                "Изменения конфигурации подписки сохраняются только на устройстве и сбрасываются при обновлении подписки.",
            "config_remove_title" to "Удалить конфигурацию?",
            "notice_config_updated" to "Конфигурация сохранена",
            "notice_config_update_failed" to "Не удалось сохранить конфигурацию",
            "notice_config_removed" to "Конфигурация удалена",
            "notice_config_remove_failed" to "Не удалось удалить конфигурацию",
        ).forEach { (name, value) ->
            assertContains(russian, "<string name=\"$name\">$value</string>")
        }
        assertContains(russian, "<string name=\"notice_config_update_failed_detail\">Не удалось сохранить конфигурацию: %1\$s</string>")
        assertContains(russian, "<string name=\"notice_config_remove_failed_detail\">Не удалось удалить конфигурацию: %1\$s</string>")
    }

    @Test fun `infinite term wording stays unchanged`() {
        assertContains(russian, "<string name=\"home_days_left_unlimited\">Осталось ∞ дн.</string>")
    }

    @Test fun `home and apps do not repeat the same facts`() {
        val home = File("src/commonMain/kotlin/io/hydrabox/ui/app/HomeScreen.kt").readText()
        val details = File("src/commonMain/kotlin/io/hydrabox/ui/app/DetailScreens.kt").readText()
        assertEquals(1, Regex("state\\.exit\\.countryCode").findAll(home).count())
        assertFalse("Res.string.apps_body_" in details)
    }

    @Test fun `resource files contain only copy used by the interface`() {
        val code =
            File("src")
                .walkTopDown()
                .filter { it.isFile && it.extension == "kt" }
                .joinToString("\n") { it.readText() }
        val names = Regex("<string name=\"([^\"]+)\"").findAll(russian).map { it.groupValues[1] }.toList()
        assertEquals(emptyList(), names.filterNot { "Res.string.$it" in code })
    }
}
