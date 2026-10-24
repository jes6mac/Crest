using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record GetElementHiding(Guid SpaceId, SiteOrigin Origin) : Query<ElementHidingState> {
    #region Actions - Answering

    internal override ElementHidingState Answer(CrestApp app) => app.Device.ElementHiding(SpaceId, Origin);

    #endregion
}
