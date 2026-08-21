import 'package:flutter_test/flutter_test.dart';
import 'package:onlystudy/models/bili_models.dart';
import 'package:onlystudy/services/bili_failure.dart';
import 'package:onlystudy/services/auth_service.dart';
import 'package:onlystudy/services/favorites_catalog.dart';
import 'package:onlystudy/services/home_library_controller.dart';
import 'package:onlystudy/services/up_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可编程 [FavoritesCatalog] 替身：返回预设的收藏夹/合集数据。
class _FakeCatalog extends FavoritesCatalog {
  List<Folder> folders = [];
  List<Season> seasons = [];
  bool throwOnFolders = false;

  int folderCalls = 0;
  int seasonCalls = 0;

  @override
  Future<List<Folder>> getFavoriteFolders({int pn = 1, int ps = 20}) async {
    folderCalls++;
    if (throwOnFolders) throw Exception('network');
    // 模拟分页：每页 ps 个
    final start = (pn - 1) * ps;
    return folders.skip(start).take(ps).toList();
  }

  @override
  Future<List<Season>> getSubscribedSeasons({int pn = 1, int ps = 20}) async {
    seasonCalls++;
    final start = (pn - 1) * ps;
    return seasons.skip(start).take(ps).toList();
  }
}

/// 可编程 [UpLibrary] 替身：返回预设的 UP 信息。
class _FakeUpLibrary extends UpLibrary {
  Map<int, BiliUserInfo> upInfo = {};
  Set<int> failingMids = {};

  @override
  Future<BiliUserInfo> getUpInfo(int mid) async {
    if (failingMids.contains(mid)) {
      throw const BiliFailure(BiliFailureKind.bizError, code: -799);
    }
    return upInfo[mid] ??
        BiliUserInfo(
          mid: mid,
          name: 'up$mid',
          face: '',
          sign: '',
          level: 1,
          fans: 0,
          following: 0,
          likes: 0,
          archiveView: 0,
          videoCount: 10,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeCatalog catalog;
  late _FakeUpLibrary upLibrary;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = _FakeCatalog();
    upLibrary = _FakeUpLibrary();
  });

  Folder folder(int id) => Folder(
    id: id,
    title: 'folder$id',
    cover: '',
    mediaCount: 5,
    upper: BiliUpper(mid: 1, name: 'up'),
    favState: 1,
  );

  Season season(int id) => Season(
    id: id,
    title: 'season$id',
    cover: '',
    mediaCount: 3,
    upper: BiliUpper(mid: 2, name: 'up2'),
  );

  group('HomeLibraryController.refresh', () {
    test('加载可见收藏夹/合集/UP 并发布 HomeLibraryLoaded', () async {
      SharedPreferences.setMockInitialValues({
        'visible_folder_ids': ['1', '2'],
        'visible_season_ids': ['3'],
        'visible_up_ids': ['7', '8'],
      });
      catalog.folders = [folder(1), folder(2)];
      catalog.seasons = [season(3)];
      final controller = HomeLibraryController(
        catalog: catalog,
        upLibrary: upLibrary,
      );

      await controller.init();
      await controller.refresh();

      final state = controller.value;
      expect(state, isA<HomeLibraryLoaded>());
      final loaded = state as HomeLibraryLoaded;
      expect(loaded.items.whereType<FolderItem>().length, 2);
      expect(loaded.items.whereType<SeasonItem>().length, 1);
      expect(loaded.items.whereType<UpItem>().length, 2);
      expect(loaded.items.whereType<UpItem>().first.user.name, 'up7');
    });

    test('收藏夹分页扫描超过 5 页时停止（静默省略未找到项）', () async {
      // 可见 ID 有 120 个，但只扫描 5 页（100 个），剩余 20 个静默省略
      catalog.folders = List.generate(120, (i) => folder(i + 1));
      SharedPreferences.setMockInitialValues({
        'visible_folder_ids': List.generate(120, (i) => (i + 1).toString()),
      });
      final controller = HomeLibraryController(
        catalog: catalog,
        upLibrary: upLibrary,
      );

      await controller.init();
      await controller.refresh();

      // 5 页后停止，只找到前 100 个，剩余 20 个静默省略
      expect(catalog.folderCalls, 5);
      final loaded = controller.value as HomeLibraryLoaded;
      expect(loaded.items.length, 100);
    });

    test('网络错误发布 HomeLibraryError', () async {
      SharedPreferences.setMockInitialValues({
        'visible_folder_ids': ['1'],
      });
      catalog.throwOnFolders = true;
      final controller = HomeLibraryController(
        catalog: catalog,
        upLibrary: upLibrary,
      );

      await controller.init();
      await controller.refresh();

      expect(controller.value, isA<HomeLibraryError>());
    });

    test('没有可见内容时发布空列表', () async {
      final controller = HomeLibraryController(
        catalog: catalog,
        upLibrary: upLibrary,
      );
      await controller.init();
      await controller.refresh();
      final loaded = controller.value as HomeLibraryLoaded;
      expect(loaded.items, isEmpty);
    });
  });

  group('HomeLibraryController 锁定状态', () {
    test('init 读取锁定状态', () async {
      SharedPreferences.setMockInitialValues({'folder_is_locked': true});
      final controller = HomeLibraryController(
        catalog: catalog,
        upLibrary: upLibrary,
      );
      await controller.init();
      expect(controller.isLocked, isTrue);
    });

    test('setLocked 更新状态并持久化', () async {
      final controller = HomeLibraryController(
        catalog: catalog,
        upLibrary: upLibrary,
      );
      await controller.init();
      expect(controller.isLocked, isFalse);

      await controller.setLocked(true);
      expect(controller.isLocked, isTrue);
      expect(await AuthService().isFolderSelectionLocked(), isTrue);
    });

    test('checkLockPassword 校验通过后解锁', () async {
      final controller = HomeLibraryController(
        catalog: catalog,
        upLibrary: upLibrary,
      );
      await controller.init();
      await controller.setLockPassword('secret');
      expect(controller.isLocked, isTrue);

      final ok = await controller.checkLockPassword('secret');
      expect(ok, isTrue);
      expect(controller.isLocked, isFalse);
    });
  });

  group('HomeLibraryController UP 容错', () {
    test('单个 UP 风控失败（BiliFailure）不影响主页加载', () async {
      SharedPreferences.setMockInitialValues({
        'visible_up_ids': ['111', '222'],
      });
      // 第一个 UP 抛风控 BiliFailure，第二个正常
      final flakyUp = _FakeUpLibrary()
        ..failingMids = {111};

      final controller = HomeLibraryController(
        catalog: catalog,
        upLibrary: flakyUp,
      );
      await controller.init();
      await controller.refresh();

      expect(controller.value, isA<HomeLibraryLoaded>());
      final loaded = controller.value as HomeLibraryLoaded;
      expect(loaded.items, isNotEmpty);
    });
  });
}
