using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record ForgetPageElementRule(Guid SpaceId, Guid RuleId) : Intent {
    #region Actions - Element hiding

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.ForgetElement(SpaceId, RuleId, changes));

    #endregion
}
