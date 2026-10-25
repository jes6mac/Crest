using CrestCore.Application;

namespace CrestCore.Contracts;

/// <summary>Shows a hidden target in the requesting Space without disabling its global rule elsewhere.</summary>
public sealed record ShowPageElement(Guid SpaceId, Guid RuleId) : Intent {
    #region Actions - Element hiding

    /// <summary>Asks the device to choose a local-rule removal or a scoped visibility exception.</summary>
    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.ShowElement(SpaceId, RuleId, changes));

    #endregion
}
