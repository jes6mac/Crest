using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed partial class Device {
    #region Variables

    private readonly ElementHidingLedger keptElements = new();
    private readonly ElementHidingLedger passingElements = new();
    private long elementHidingRevision;

    #endregion

    #region Actions - Element hiding

    internal ElementHidingState ElementHiding(Guid spaceId, SiteOrigin origin) {
        var (keeps, isPrivate) = ElementHidingScope(spaceId);
        if (!origin.IsValid) throw new Rejected(new InvalidSiteOrigin(origin));
        lock (gate) {
            var local = keeps ? keptElements : passingElements;
            var rules = keptElements.Rules.Where(rule => rule.SpaceId is null)
                .Concat(local.Rules.Where(rule => rule.SpaceId == spaceId)).Where(rule => rule.Origin == origin);
            return new(isPrivate, keeps && !isPrivate,
                [.. rules.Select(rule => new ElementHidingEntry(rule, local.Follows(spaceId, rule.Id)))]);
        }
    }

    internal void HideElement(Guid spaceId, ElementHidingRule rule, ChangeFeed changes) =>
        HideElements(spaceId, [rule], changes);

    /// Validate the complete selection before changing either rules or exceptions.
    internal void HideElements(Guid spaceId, IReadOnlyList<ElementHidingRule> rules, ChangeFeed changes) {
        var (keeps, isPrivate) = ElementHidingScope(spaceId);
        foreach (var rule in rules) {
            if (!rule.IsValid || rule.SpaceId is { } owner && owner != spaceId)
                throw new Rejected(new InvalidElementHidingRule());
            if (rule.SpaceId is null && (!keeps || isPrivate))
                throw new Rejected(new GlobalElementHidingUnavailable());
        }
        lock (gate) {
            var ledger = keeps ? keptElements : passingElements;
            var additions = rules.DistinctBy(rule => (rule.SpaceId, rule.Origin, rule.Selector, rule.TagName))
                .Where(rule => !ledger.Rules.Any(existing => existing.SpaceId == rule.SpaceId
                    && existing.Origin == rule.Origin && existing.Selector == rule.Selector && existing.TagName == rule.TagName))
                .ToArray();
            if (ledger.Rules.Count + additions.Length > ElementHidingLedger.MaximumRules)
                throw new Rejected(new ElementHidingLimitReached(ElementHidingLedger.MaximumRules));
            foreach (var site in additions.GroupBy(rule => rule.Origin)) {
                int count = keptElements.Rules.Count(existing => existing.SpaceId is null && existing.Origin == site.Key)
                    + ledger.Rules.Count(existing => existing.SpaceId == spaceId && existing.Origin == site.Key);
                if (count + site.Count() > ElementHidingLedger.MaximumRulesPerSite)
                    throw new Rejected(new ElementHidingLimitReached(ElementHidingLedger.MaximumRulesPerSite));
            }
            bool changed = false;
            foreach (var rule in additions) changed |= ledger.Add(rule);
            foreach (var rule in rules.Where(rule => rule.SpaceId is null)) {
                var existing = ledger.Rules.First(value => value.SpaceId is null && value.Origin == rule.Origin
                    && value.Selector == rule.Selector && value.TagName == rule.TagName);
                changed |= ledger.Inherit(spaceId, existing.Id);
            }
            if (changed) PublishElementHiding(keeps, changes);
        }
    }

    internal void ShowElement(Guid spaceId, Guid ruleId, ChangeFeed changes) {
        var (keeps, _) = ElementHidingScope(spaceId);
        lock (gate) {
            var ledger = keeps ? keptElements : passingElements;
            bool global = keptElements.Rules.Any(rule => rule.Id == ruleId && rule.SpaceId is null);
            bool changed = global ? ledger.Except(spaceId, ruleId)
                : ledger.Rules.Any(rule => rule.Id == ruleId && rule.SpaceId == spaceId) && ledger.Remove(ruleId);
            if (changed) PublishElementHiding(keeps, changes);
        }
    }

    internal void FollowElement(Guid spaceId, Guid ruleId, ChangeFeed changes) {
        var (keeps, _) = ElementHidingScope(spaceId);
        lock (gate) {
            if ((keeps ? keptElements : passingElements).Inherit(spaceId, ruleId)) PublishElementHiding(keeps, changes);
        }
    }

    internal void ForgetElement(Guid spaceId, Guid ruleId, ChangeFeed changes) {
        var (keeps, isPrivate) = ElementHidingScope(spaceId);
        lock (gate) {
            bool global = keptElements.Rules.Any(rule => rule.Id == ruleId && rule.SpaceId is null);
            if (global && (!keeps || isPrivate)) throw new Rejected(new GlobalElementHidingUnavailable());
            var ledger = keeps ? keptElements : passingElements;
            if (!global && !ledger.Rules.Any(rule => rule.Id == ruleId && rule.SpaceId == spaceId)) return;
            bool changed = ledger.Remove(ruleId);
            if (global) changed |= passingElements.Remove(ruleId);
            if (changed) PublishElementHiding(keeps, changes);
        }
    }

    private (bool Keeps, bool IsPrivate) ElementHidingScope(Guid spaceId) {
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        Guid? persistent;
        lock (gate) {
            persistent = persistentWorkspace;
            attached = [.. workspaces.OrderByDescending(entry => entry.Key == persistent)];
        }
        foreach (var (workspaceId, authority) in attached) {
            if (authority.Current.Spaces.FirstOrDefault(space => space.Id == spaceId) is not { } space) continue;
            if (authority.IsLocked(space)) throw new Rejected(new SpaceLocked(spaceId));
            return (workspaceId == persistent, authority.IsPrivateBrowsing);
        }
        throw new Rejected(new UnknownSpace(spaceId));
    }

    private void PublishElementHiding(bool keeps, ChangeFeed changes) {
        if (keeps) storage?.EnqueueDevice(Records());
        changes.Publish(new ElementHidingChanged(++elementHidingRevision));
    }

    private void ForgetElementSpaces(IReadOnlySet<Guid> spaceIds, bool includeKept) {
        lock (gate) {
            bool changed = passingElements.ForgetSpaces(spaceIds);
            bool keptChanged = includeKept && keptElements.ForgetSpaces(spaceIds);
            if (keptChanged) storage?.EnqueueDevice(Records());
            if (changed || keptChanged) announce(new ElementHidingChanged(++elementHidingRevision));
        }
    }

    #endregion
}
