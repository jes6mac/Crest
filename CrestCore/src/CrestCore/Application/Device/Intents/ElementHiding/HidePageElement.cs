using CrestCore.Application;

namespace CrestCore.Contracts;

/// <summary>Saves one target for an exact origin, locally or globally. Private changes must remain Space-local.</summary>
public sealed record HidePageElement(Guid SpaceId, SiteOrigin Origin, string Selector, string TagName, string Label, bool AllSpaces) : Intent {
    #region Actions - Element hiding

    /// <summary>Assigns a device identity and delegates validation and persistence to the atomic batch path.</summary>
    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.HideElement(SpaceId, new(app.Ids.Next(), AllSpaces ? null : SpaceId, Origin, Selector, TagName, Label), changes));

    #endregion
}
