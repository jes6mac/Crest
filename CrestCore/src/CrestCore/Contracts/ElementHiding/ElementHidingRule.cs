namespace CrestCore.Contracts;

/// One element on an exact web origin. A null Space applies to every Space.
public sealed record ElementHidingRule(Guid Id, Guid? SpaceId, SiteOrigin Origin, string Selector, string TagName, string Label) {
    #region Static Variables

    public const int MaximumSelectorLength = 1_024;
    public const int MaximumLabelLength = 80;
    private static readonly HashSet<string> ProtectedTags = ["HTML", "BODY", "HEAD", "SCRIPT", "STYLE", "LINK", "META", "NOSCRIPT"];

    #endregion

    #region Variables

    public bool IsValid => Id != Guid.Empty && Origin.IsValid && Origin.Scheme is "http" or "https"
        && !string.IsNullOrWhiteSpace(Selector) && Selector.Length <= MaximumSelectorLength
        && TagName.Length is > 0 and <= 64 && TagName.All(character => char.IsAsciiLetterOrDigit(character) || character == '-')
        && !ProtectedTags.Contains(TagName.ToUpperInvariant()) && Label.Length <= MaximumLabelLength;

    #endregion
}
