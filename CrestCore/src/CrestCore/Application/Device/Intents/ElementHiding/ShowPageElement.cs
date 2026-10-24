using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record ShowPageElement(Guid SpaceId, Guid RuleId) : Intent {
    #region Actions - Element hiding

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.ShowElement(SpaceId, RuleId, changes));

    #endregion
}
