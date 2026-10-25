using CrestCore.Application;

namespace CrestCore.Contracts;

/// <summary>Deletes an owned local rule or a global rule when the requesting Space may change global rules.</summary>
public sealed record ForgetPageElementRule(Guid SpaceId, Guid RuleId) : Intent {
    #region Actions - Element hiding

    /// <summary>Delegates deletion and cross-Space exception cleanup to the device's authorization boundary.</summary>
    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.ForgetElement(SpaceId, RuleId, changes));

    #endregion
}
