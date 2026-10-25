using CrestCore.Application;

namespace CrestCore.Contracts;

/// <summary>Removes the current Space's exception to a global hiding rule without changing other Spaces.</summary>
public sealed record FollowPageElementRule(Guid SpaceId, Guid RuleId) : Intent {
    #region Actions - Element hiding

    /// <summary>Restores inheritance through a device turn so observers receive the updated revision.</summary>
    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.FollowElement(SpaceId, RuleId, changes));

    #endregion
}
