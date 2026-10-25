using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed partial class SqliteConnection {
    #region Actions - Element hiding

    /// <summary>Creates device-local rule and exception tables outside the synced session checkpoint.</summary>
    private void CreateElementHidingTables() {
        Execute("CREATE TABLE IF NOT EXISTS device_hidden_element (id TEXT PRIMARY KEY, space TEXT, scheme TEXT NOT NULL, "
            + "host TEXT NOT NULL, port INTEGER NOT NULL, selector TEXT NOT NULL, tag TEXT NOT NULL, label TEXT NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_hidden_element_exception (space TEXT NOT NULL, rule TEXT NOT NULL, PRIMARY KEY (space, rule))");
    }

    /// <summary>Restores rule order while ignoring invalid rows and exceptions that no longer reference a global rule.</summary>
    private ElementHidingRecords ReadElementHiding() {
        var rules = new List<ElementHidingRule>();
        Rows("SELECT id, space, scheme, host, port, selector, tag, label FROM device_hidden_element ORDER BY position", statement => {
            if (Identity(statement, 0) is not { } id) return;
            Guid? space = Identity(statement, 1);
            if (!Sqlite.ColumnIsNull(statement, 1) && space is null) return;
            var origin = new SiteOrigin(Sqlite.ColumnText(statement, 2), Sqlite.ColumnText(statement, 3), Sqlite.sqlite3_column_int(statement, 4));
            var rule = new ElementHidingRule(id, space, origin, Sqlite.ColumnText(statement, 5), Sqlite.ColumnText(statement, 6),
                Sqlite.ColumnText(statement, 7));
            if (rule.IsValid) rules.Add(rule);
        });
        var exceptions = new List<ElementHidingException>();
        Rows("SELECT space, rule FROM device_hidden_element_exception ORDER BY space, rule", statement => {
            if (Identity(statement, 0) is { } space && Identity(statement, 1) is { } rule
                && rules.Any(value => value.Id == rule && value.SpaceId is null)) exceptions.Add(new(space, rule));
        });
        return new(rules, exceptions);
    }

    /// <summary>Replaces persisted rules and exceptions inside the caller's device-write transaction.
    /// The supplied snapshot contains kept rules only; private-session state must never reach this writer.</summary>
    private void WriteElementHiding(ElementHidingRecords records) {
        Execute("DELETE FROM device_hidden_element");
        Execute("DELETE FROM device_hidden_element_exception");
        for (int position = 0; position < records.Rules.Count; position++) {
            var rule = records.Rules[position];
            int index = position;
            Insert("INSERT INTO device_hidden_element(id, space, scheme, host, port, selector, tag, label, position) VALUES(?,?,?,?,?,?,?,?,?)",
                statement => {
                    Bind(statement, 1, Spelling(rule.Id));
                    Bind(statement, 2, rule.SpaceId is { } space ? Spelling(space) : null);
                    Bind(statement, 3, rule.Origin.Scheme);
                    Bind(statement, 4, rule.Origin.Host);
                    Checked(Sqlite.sqlite3_bind_int64(statement, 5, rule.Origin.Port));
                    Bind(statement, 6, rule.Selector);
                    Bind(statement, 7, rule.TagName);
                    Bind(statement, 8, rule.Label);
                    Checked(Sqlite.sqlite3_bind_int64(statement, 9, index));
                });
        }
        foreach (var exception in records.Exceptions)
            Insert("INSERT INTO device_hidden_element_exception(space, rule) VALUES(?,?)", statement => {
                Bind(statement, 1, Spelling(exception.SpaceId));
                Bind(statement, 2, Spelling(exception.RuleId));
            });
    }

    #endregion
}
