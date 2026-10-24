using CrestCore.Contracts;

namespace CrestCore.Application;

#region Types

internal sealed record ElementHidingException(Guid SpaceId, Guid RuleId);
internal sealed record ElementHidingRecords(IReadOnlyList<ElementHidingRule> Rules, IReadOnlyList<ElementHidingException> Exceptions);

#endregion

/// The device lock guards this ledger. Kept and temporary rules have separate ledgers.
internal sealed class ElementHidingLedger {
    #region Static Variables

    public const int MaximumRules = 512;
    public const int MaximumRulesPerSite = 100;

    #endregion

    #region Variables

    private readonly List<ElementHidingRule> rules = [];
    private readonly HashSet<ElementHidingException> exceptions = [];
    public IReadOnlyList<ElementHidingRule> Rules => rules;
    public ElementHidingRecords Records => new([.. rules], [.. exceptions.OrderBy(value => value.SpaceId).ThenBy(value => value.RuleId)]);

    #endregion

    #region Actions - Rules

    public void Restore(ElementHidingRecords records) {
        rules.Clear();
        rules.AddRange(records.Rules.Where(rule => rule.IsValid).Take(MaximumRules));
        exceptions.Clear();
        exceptions.UnionWith(records.Exceptions.Where(value => rules.Any(rule => rule.Id == value.RuleId && rule.SpaceId is null)));
    }

    public bool Add(ElementHidingRule rule) {
        if (!rule.IsValid) throw new Rejected(new InvalidElementHidingRule());
        if (rules.Any(existing => existing.SpaceId == rule.SpaceId && existing.Origin == rule.Origin
            && existing.Selector == rule.Selector && existing.TagName == rule.TagName)) return false;
        if (rules.Count >= MaximumRules) throw new Rejected(new ElementHidingLimitReached(MaximumRules));
        rules.Add(rule);
        return true;
    }

    public bool Except(Guid spaceId, Guid ruleId) => exceptions.Add(new(spaceId, ruleId));
    public bool Follows(Guid spaceId, Guid ruleId) => !exceptions.Contains(new(spaceId, ruleId));
    public bool Inherit(Guid spaceId, Guid ruleId) => exceptions.Remove(new(spaceId, ruleId));

    public bool Remove(Guid ruleId) {
        bool changed = rules.RemoveAll(rule => rule.Id == ruleId) > 0;
        return exceptions.RemoveWhere(value => value.RuleId == ruleId) > 0 || changed;
    }

    public bool ForgetSpaces(IReadOnlySet<Guid> spaceIds) {
        bool changed = rules.RemoveAll(rule => rule.SpaceId is { } space && spaceIds.Contains(space)) > 0;
        return exceptions.RemoveWhere(value => spaceIds.Contains(value.SpaceId)) > 0 || changed;
    }

    #endregion
}
