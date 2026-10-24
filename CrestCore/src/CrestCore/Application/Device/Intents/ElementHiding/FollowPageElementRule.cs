using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record FollowPageElementRule(Guid SpaceId, Guid RuleId) : Intent {
    #region Actions - Element hiding

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.FollowElement(SpaceId, RuleId, changes));

    #endregion
}
