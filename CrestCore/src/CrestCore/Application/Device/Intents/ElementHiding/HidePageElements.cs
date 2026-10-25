using CrestCore.Application;

namespace CrestCore.Contracts;

/// <summary>Saves a complete preview batch for an exact origin. Any invalid target or forbidden scope rejects the batch.</summary>
public sealed record HidePageElements(Guid SpaceId, SiteOrigin Origin, IReadOnlyList<ElementHidingTarget> Targets, bool AllSpaces) : Intent {
    #region Actions - Element hiding

    /// <summary>Assigns rule identities and submits every target in one device turn without partial saves.</summary>
    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.HideElements(SpaceId,
            [.. Targets.Select(target => new ElementHidingRule(app.Ids.Next(), AllSpaces ? null : SpaceId,
                Origin, target.Selector, target.TagName, target.Label))], changes));

    #endregion
}
