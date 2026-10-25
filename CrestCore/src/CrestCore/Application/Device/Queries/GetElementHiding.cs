using CrestCore.Application;

namespace CrestCore.Contracts;

/// <summary>Reads effective rules and edit permissions for one unlocked Space and exact web origin.</summary>
public sealed record GetElementHiding(Guid SpaceId, SiteOrigin Origin) : Query<ElementHidingState> {
    #region Actions - Answering

    /// <summary>Reads through the device so private exceptions and access checks use the owning workspace.</summary>
    internal override ElementHidingState Answer(CrestApp app) => app.Device.ElementHiding(SpaceId, Origin);

    #endregion
}
