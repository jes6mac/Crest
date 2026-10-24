namespace CrestCore.Contracts;

public sealed record ElementHidingEntry(ElementHidingRule Rule, bool IsHidden);
public sealed record ElementHidingState(bool IsPrivate, bool CanChangeGlobal, IReadOnlyList<ElementHidingEntry> Entries);
public sealed record ElementHidingChanged(long Revision) : Change;
public sealed record InvalidElementHidingRule : Rejection;
public sealed record GlobalElementHidingUnavailable : Rejection;
public sealed record ElementHidingLimitReached(int Limit) : Rejection;
public sealed record ElementHidingTarget(string Selector, string TagName, string Label);
