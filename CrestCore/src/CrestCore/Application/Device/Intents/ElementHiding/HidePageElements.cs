using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record HidePageElements(Guid SpaceId, SiteOrigin Origin, IReadOnlyList<ElementHidingTarget> Targets, bool AllSpaces) : Intent {
    #region Actions - Element hiding

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.HideElements(SpaceId,
            [.. Targets.Select(target => new ElementHidingRule(app.Ids.Next(), AllSpaces ? null : SpaceId,
                Origin, target.Selector, target.TagName, target.Label))], changes));

    #endregion
}
