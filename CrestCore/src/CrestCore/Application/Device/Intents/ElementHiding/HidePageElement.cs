using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record HidePageElement(Guid SpaceId, SiteOrigin Origin, string Selector, string TagName, string Label, bool AllSpaces) : Intent {
    #region Actions - Element hiding

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.HideElement(SpaceId, new(app.Ids.Next(), AllSpaces ? null : SpaceId, Origin, Selector, TagName, Label), changes));

    #endregion
}
