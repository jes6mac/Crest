using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void ElementHidingSessionCommitsAllTargetsOrNone() {
        using var directory = new StorageDirectory();
        var (app, _, spaces) = DeviceApp(directory);
        using var disposal = app;
        var space = SpaceId(spaces[0]!);
        var origin = new SiteOrigin("https", "mask.example", 443);
        ElementHidingTarget[] targets = [new("#first", "DIV", "First"), new("body", "BODY", "Page")];
        Assert.IsType<InvalidElementHidingRule>(Assert.Throws<Rejected>(() =>
            app.Send(new HidePageElements(space, origin, targets, false))).Rejection);
        Assert.Empty(app.Query(new GetElementHiding(space, origin)).Entries);
        targets = [new("#first", "DIV", "First"), new("#second", "ASIDE", "Second")];
        app.Send(new HidePageElements(space, origin, targets, true));
        var entries = app.Query(new GetElementHiding(space, origin)).Entries;
        Assert.Equal(2, entries.Count);
        app.Send(new ShowPageElement(space, entries[0].Rule.Id));
        app.Send(new HidePageElements(space, origin, targets, true));
        Assert.All(app.Query(new GetElementHiding(space, origin)).Entries, entry => Assert.True(entry.IsHidden));
        var tooMany = Enumerable.Range(0, 100).Select(index => new ElementHidingTarget($"#next-{index}", "DIV", "Next")).ToArray();
        Assert.IsType<ElementHidingLimitReached>(Assert.Throws<Rejected>(() =>
            app.Send(new HidePageElements(space, origin, tooMany, false))).Rejection);
        Assert.Equal(2, app.Query(new GetElementHiding(space, origin)).Entries.Count);
        var workspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
        var privateSpace = app.Workspace(workspace).Current.Spaces[0].Id;
        Assert.IsType<GlobalElementHidingUnavailable>(Assert.Throws<Rejected>(() =>
            app.Send(new HidePageElements(privateSpace, origin, targets, true))).Rejection);
        Assert.Equal(2, app.Query(new GetElementHiding(privateSpace, origin)).Entries.Count);
        app.Send(new HidePageElements(privateSpace, origin, targets, false));
        Assert.Equal(4, app.Query(new GetElementHiding(privateSpace, origin)).Entries.Count);
        Assert.Equal(2, app.Device.Records().ElementHiding.Rules.Count);
    }

    [Fact]
    public void ElementHidingRulesAndSpaceExceptionsSurviveRelaunchOutsideTheSyncedSession() {
        using var directory = new StorageDirectory();
        var origin = new SiteOrigin("https", "mask.example", 443);
        Guid work, personal, global;
        {
            var (app, _, spaces) = DeviceApp(directory);
            using var disposal = app;
            work = SpaceId(spaces[0]!);
            personal = SpaceId(spaces[1]!);
            app.Send(new HidePageElement(work, origin, "#newsletter", "ASIDE", "Newsletter", true));
            global = Assert.Single(app.Query(new GetElementHiding(work, origin)).Entries).Rule.Id;
            app.Send(new ShowPageElement(personal, global));
            app.Send(new HidePageElement(personal, origin, "#local", "ASIDE", "Local", false));
            Assert.True(Assert.Single(app.Query(new GetElementHiding(work, origin)).Entries).IsHidden);
            Assert.False(app.Query(new GetElementHiding(personal, origin)).Entries.Single(entry => entry.Rule.Id == global).IsHidden);
        }
        using (var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadOnly)) {
            Assert.Equal(2, connection.ReadDevice().ElementHiding.Rules.Count);
            Assert.Single(connection.ReadDevice().ElementHiding.Exceptions);
        }
        Assert.DoesNotContain("#newsletter", Encoding.UTF8.GetString(StoredParts(directory.File)["core"]), StringComparison.Ordinal);
        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        Assert.True(Assert.Single(relaunched.Query(new GetElementHiding(work, origin)).Entries).IsHidden);
        var entries = relaunched.Query(new GetElementHiding(personal, origin)).Entries;
        Assert.False(entries.Single(entry => entry.Rule.Id == global).IsHidden);
        Assert.True(entries.Single(entry => entry.Rule.SpaceId == personal).IsHidden);
        relaunched.Send(new FollowPageElementRule(personal, global));
        Assert.All(relaunched.Query(new GetElementHiding(personal, origin)).Entries, entry => Assert.True(entry.IsHidden));
        Assert.Empty(relaunched.Query(new GetElementHiding(work, new SiteOrigin("https", "other.example", 443))).Entries);
    }

    [Fact]
    public void ElementHidingPrivateChangesAreTemporaryAndCannotEditGlobalRules() {
        using var directory = new StorageDirectory();
        var (app, _, spaces) = DeviceApp(directory);
        using var disposal = app;
        var work = SpaceId(spaces[0]!);
        var origin = new SiteOrigin("https", "mask.example", 443);
        app.Send(new HidePageElement(work, origin, "#newsletter", "ASIDE", "Newsletter", true));
        var global = Assert.Single(app.Query(new GetElementHiding(work, origin)).Entries).Rule.Id;
        var workspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
        var space = app.Workspace(workspace).Current.Spaces[0].Id;
        var inherited = app.Query(new GetElementHiding(space, origin));
        Assert.True(inherited.IsPrivate);
        Assert.False(inherited.CanChangeGlobal);
        Assert.True(Assert.Single(inherited.Entries).IsHidden);
        var before = app.Device.Records().ElementHiding;
        app.Send(new ShowPageElement(space, global));
        app.Send(new HidePageElement(space, origin, "#private-only", "ASIDE", "Private content", false));
        Assert.Equal(new GlobalElementHidingUnavailable(), Assert.Throws<Rejected>(() =>
            app.Send(new HidePageElement(space, origin, "#forbidden", "ASIDE", "Forbidden", true))).Rejection);
        Assert.Equal(new GlobalElementHidingUnavailable(), Assert.Throws<Rejected>(() =>
            app.Send(new ForgetPageElementRule(space, global))).Rejection);
        var after = app.Device.Records().ElementHiding;
        Assert.Equal(before.Rules, after.Rules);
        Assert.Equal(before.Exceptions, after.Exceptions);
        Assert.True(Assert.Single(app.Query(new GetElementHiding(work, origin)).Entries).IsHidden);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, false, null, null, [], true));
        app.Send(new ResetPrivateBrowsing(workspace, window));
        Assert.Equal(new UnknownSpace(space), Assert.Throws<Rejected>(() => app.Query(new GetElementHiding(space, origin))).Rejection);
        var resetSpace = app.Workspace(workspace).Current.Spaces[0].Id;
        Assert.True(Assert.Single(app.Query(new GetElementHiding(resetSpace, origin)).Entries).IsHidden);
        app.Send(new ShowPageElement(resetSpace, global));
        app.Send(new CloseWorkspace(workspace));
        Assert.Equal(new UnknownSpace(space), Assert.Throws<Rejected>(() => app.Query(new GetElementHiding(space, origin))).Rejection);
        var reopened = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
        var fresh = app.Workspace(reopened).Current.Spaces[0].Id;
        Assert.True(Assert.Single(app.Query(new GetElementHiding(fresh, origin)).Entries).IsHidden);
        Assert.DoesNotContain(app.Device.Records().ElementHiding.Rules, rule => rule.Selector == "#private-only");
    }

    [Fact]
    public void ElementHidingGlobalRemovalPreservesLocalRulesAndClearsExceptions() {
        using var directory = new StorageDirectory();
        var (app, _, spaces) = DeviceApp(directory);
        using var disposal = app;
        var work = SpaceId(spaces[0]!);
        var personal = SpaceId(spaces[1]!);
        var origin = new SiteOrigin("https", "mask.example", 443);
        app.Send(new HidePageElement(work, origin, "#newsletter", "ASIDE", "Newsletter", false));
        var local = Assert.Single(app.Query(new GetElementHiding(work, origin)).Entries).Rule.Id;
        app.Send(new HidePageElement(personal, origin, "#newsletter", "ASIDE", "Newsletter", true));
        var global = Assert.Single(app.Query(new GetElementHiding(personal, origin)).Entries).Rule.Id;
        app.Send(new ShowPageElement(work, global));
        app.Send(new ForgetPageElementRule(personal, local));
        Assert.Contains(app.Query(new GetElementHiding(work, origin)).Entries, entry => entry.Rule.Id == local);
        app.Send(new ForgetPageElementRule(personal, global));
        Assert.Equal(local, Assert.Single(app.Query(new GetElementHiding(work, origin)).Entries).Rule.Id);
        Assert.Empty(app.Query(new GetElementHiding(personal, origin)).Entries);
        Assert.Empty(app.Device.Records().ElementHiding.Exceptions);
    }

    [Fact]
    public void ElementHidingRejectsUnknownOwnersAndUnsafeTargets() {
        using var directory = new StorageDirectory();
        var (app, _, spaces) = DeviceApp(directory);
        using var disposal = app;
        var space = SpaceId(spaces[0]!);
        var origin = new SiteOrigin("https", "mask.example", 443);
        var missing = Guid.NewGuid();
        Assert.Equal(new UnknownSpace(missing), Assert.Throws<Rejected>(() =>
            app.Send(new HidePageElement(missing, origin, "#item", "DIV", "Item", false))).Rejection);
        Assert.Equal(new InvalidElementHidingRule(), Assert.Throws<Rejected>(() =>
            app.Send(new HidePageElement(space, origin, "body", "BODY", "Page", false))).Rejection);
        Assert.Equal(new InvalidElementHidingRule(), Assert.Throws<Rejected>(() =>
            app.Send(new HidePageElement(space, origin, new string('x', 1_025), "DIV", "Item", false))).Rejection);
        Assert.Empty(app.Query(new GetElementHiding(space, origin)).Entries);
    }
}
