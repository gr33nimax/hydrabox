package io.hydrabox.core.storage

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver

object StorageTestDriver {
    fun previousVersion(): SqlDriver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also { driver ->
        driver.execute(null, "CREATE TABLE settings (setting_key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)", 0)
        driver.execute(null, "INSERT INTO settings(setting_key, value) VALUES ('theme', 'dark')", 0)
    }

    fun currentVersion(): SqlDriver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also(StorageDatabase.Schema::create)
}
