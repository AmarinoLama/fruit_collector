import 'dart:async';
import 'dart:io';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:fruit_collector/components/HUD/buttons_game/custom_joystick.dart';
import 'package:fruit_collector/components/HUD/widgets/achievement_details.dart';
import 'package:fruit_collector/components/HUD/widgets/main_menu/main_menu.dart';
import 'package:fruit_collector/components/bbdd/models/game_achievement.dart';
import 'package:fruit_collector/components/bbdd/models/game_level.dart';
import 'package:fruit_collector/components/bbdd/services/achievement_service.dart';
import 'package:fruit_collector/components/bbdd/services/level_service.dart';
import 'package:fruit_collector/components/bbdd/services/settings_service.dart';
import 'package:fruit_collector/components/game/level/screens/death_screen.dart';
import 'package:fruit_collector/components/game/level/sound_manager.dart';
import 'package:window_size/window_size.dart';

import 'components/HUD/buttons_game/achievements_button.dart';
import 'components/HUD/buttons_game/change_player_skin_button.dart';
import 'components/HUD/buttons_game/jump_button.dart';
import 'components/HUD/buttons_game/open_level_selection.dart';
import 'components/HUD/buttons_game/open_menu_button.dart';
import 'components/HUD/widgets/achievement_toast.dart';
import 'components/HUD/widgets/achievements_menu.dart';
import 'components/HUD/widgets/character_selection.dart';
import 'components/HUD/widgets/level_selection_menu.dart';
import 'components/HUD/widgets/main_menu/game_selector.dart';
import 'components/HUD/widgets/pause_menu.dart';
import 'components/HUD/widgets/settings/settings_menu.dart';
import 'components/bbdd/models/achievement.dart';
import 'components/bbdd/models/game.dart' as models;
import 'components/bbdd/models/settings.dart';
import 'components/bbdd/services/game_service.dart';
import 'components/game/achievements/achievement_manager.dart';
import 'components/game/content/levelBasics/player.dart';
import 'components/game/content/traps/fire_block.dart';
import 'components/game/level/level.dart';
import 'components/game/level/screens/change_level_screen.dart';
import 'components/game/level/screens/credits_screen.dart';
import 'components/game/level/screens/level_summary_overlay.dart';
import 'components/game/level/screens/credits_screen.dart';

class PixelAdventure extends FlameGame
    with
        HasKeyboardHandlerComponents,
        DragCallbacks,
        HasCollisionDetection,
        TapCallbacks {
  // Logic to load the level and the player
  @override
  Color backgroundColor() => const Color(0xFF211F30);
  late CameraComponent cam;

  GameService? gameService;
  LevelService? levelService;
  SettingsService? settingsService;
  AchievementService? achievementService;

  final List<String> characters = [
    '1',
    '2',
    '3',
    'Mask Dude',
    'Ninja Frog',
    'Pink Man',
    'Virtual Guy',
  ];
  late Player player;
  late Level level;

  late Settings settings;

  List<Map<String, dynamic>> levels = [];
  List<Map<String, dynamic>> achievements = [];

  List<int> get unlockedLevelIndices =>
      levels
          .asMap()
          .entries
          .where((entry) => (entry.value['gameLevel'] as GameLevel).unlocked)
          .map((entry) => entry.key)
          .toList();

  List<int> get completedLevelIndices =>
      levels
          .asMap()
          .entries
          .where((entry) => (entry.value['gameLevel'] as GameLevel).completed)
          .map((entry) => entry.key)
          .toList();

  Map<int, int> get starsPerLevel =>
      levels.asMap().map((index, level) =>
          MapEntry(index, ((level['gameLevel'] as GameLevel).stars)));

  // Screens initializations
  late final DeathScreen deathScreen = DeathScreen(
    game: this,
    gameAdd: (component) {
      add(component);
    },
    gameRemove: (component) {
      removeWhere((component) => component is DeathScreen);
    },
    size: size,
    position: Vector2(0, 0),
  )
    ..priority = 1000;

  late var changeLevelScreen = ChangeLevelScreen(
    onCollapseEnd: () {
      overlays.add('level_summary');
      removeWhere((component) => component is Level);
    },
    onExpandEnd: () {
      gameData!.currentLevel++;
      _loadActualLevel(); // o lo que uses para cargar el siguiente
    },
  );

  late final creditsScreen = CreditsScreen(
    gameAdd: (component) => add(component),
    gameRemove: (component) => remove(component),
    game: this,
  );

  // Logic to manage the HUD, controls, size of the buttons and the positions
  late CustomJoystick customJoystick;
  ChangePlayerSkinButton? changeSkinButton;
  OpenMenuButton? menuButton;
  LevelSelection? levelSelectionButton;
  AchievementsButton? achievementsButton;
  JumpButton? jumpButton;
  bool isJoystickAdded = false;
  late final Vector2 rightControlPosition = Vector2(
    size.x - 32 - settings.controlSize,
    size.y - 32 - settings.controlSize,
  );
  late final Vector2 leftControlPosition = Vector2(
    32 - settings.controlSize,
    32 - settings.controlSize,
  );

  // Logic to manage achievements
  late final AchievementManager achievementManager = AchievementManager(
    game: this,
  );
  Achievement? currentShowedAchievement;
  Achievement? currentAchievement;
  GameAchievement? currentGameAchievement;
  Map<int, int> levelTimes = {};
  Map<int, int> levelDeaths = {};

  models.Game? gameData;

  Future<void> chargeSlot(int slot) async {
    await getGameService();
    await getLevelService();
    await getSettingsService();
    await getAchievementService();
    gameData = await gameService!.getOrCreateGameBySpace(space: slot);
    levels = await levelService!.getLevelsForGame(gameData!.id);
    settings =
    await settingsService!.getSettingsForGame(gameData!.id) as Settings;
    achievements = await achievementService!.getAchievementsForGame(
      gameData!.id,
    );
    print('change settings  : $settings');
    print('Levels  : $levels');
    print('Current Level  : ${gameData?.currentLevel}');

    loadButtonsAndHud();

    ///load first level with data
    _loadActualLevel();
  }

  @override
  FutureOr<void> onLoad() async {
    FlameAudio.bgm.initialize();

    // Load all the images and sounds in cache
    await images.loadAllImages();
    await SoundManager().init();

    // Load the player skin
    player = Player(character: characters[gameData?.currentCharacter ?? 0]);

    addOverlays();

    // Open the main menu
    pauseEngine();
    overlays.add(MainMenu.id);

    return super.onLoad();
  }

  void loadButtonsAndHud() {
    print('settings : $settings');

    initializateButtons();

    addAllButtons();
  }

  @override
  void onDispose() {
    super.onDispose();
  }

  void initializateButtons() {
    changeSkinButton =
        changeSkinButton ??
            ChangePlayerSkinButton(
              changeCharacter: openChangeCharacterMenu,
              buttonSize: settings.hudSize,
            );
    menuButton = menuButton ?? OpenMenuButton(buttonSize: settings.hudSize);
    levelSelectionButton =
        levelSelectionButton ??
            LevelSelection(
              buttonSize: settings.hudSize,
              onTap: openLevelSelectionMenu,
            );
    achievementsButton =
        achievementsButton ?? AchievementsButton(buttonSize: settings.hudSize);
    jumpButton = JumpButton(settings.controlSize);
  }

  void addOverlays() {
    overlays.addEntry(PauseMenu.id, (context, game) => PauseMenu(this));
    overlays.addEntry(SettingsMenu.id, (context, game) => SettingsMenu(this));
    overlays.addEntry(
      CharacterSelection.id,
          (context, game) => CharacterSelection(this),
    );
    overlays.addEntry(
      AchievementMenu.id,
          (context, game) => AchievementMenu(this, achievements),
    );
    overlays.addEntry(
      AchievementDetails.id,
          (context, game) => AchievementDetails(this, currentAchievement!, currentGameAchievement!),
    );
    overlays.addEntry(
      'level_summary',
          (context, game) =>
          LevelSummaryOverlay(
            levelName: level.levelName,
            difficulty: levels[gameData!.currentLevel]['level'].difficulty,
            deaths: level.minorDeaths,
            stars: level.starsCollected,
            time: level.minorLevelTime,
            onContinue: () {
              overlays.remove('level_summary');
              changeLevelScreen.startExpand(); // Animación inversa
            },
          ),
    );
    overlays.addEntry(
        CharacterSelection.id, (context, game) => CharacterSelection(this));
    overlays.addEntry(AchievementMenu.id, (context, game) =>
        AchievementMenu(this, achievements));
    overlays.addEntry(MainMenu.id, (context, game) => MainMenu(this));
    overlays.addEntry(GameSelector.id, (context, game) => GameSelector(this));
    overlays.addEntry(AchievementToast.id, (context, game) {
      final pixelAdventure = game as PixelAdventure;
      return pixelAdventure.currentShowedAchievement == null
          ? const SizedBox.shrink()
          : AchievementToast(
        achievement: pixelAdventure.currentShowedAchievement!,
        onDismiss: () => overlays.remove(AchievementToast.id),
      );
    });
    overlays.addEntry(
      LevelSelectionMenu.id,
          (context, game) =>
          LevelSelectionMenu(
            game: this,
            totalLevels: levels.length,
            onLevelSelected: (level) async {
              final GameService service = await GameService.getInstance();
              await service.saveGameBySpace(game: gameData);

              overlays.remove(LevelSelectionMenu.id);
              resumeEngine();
              gameData?.currentLevel = level;
              _loadActualLevel();
            },
          ),
    );
  }

  void reloadAllButtons() {
    removeControls();
    for (var component in children.where(
          (component) =>
      component is ChangePlayerSkinButton ||
          component is LevelSelection ||
          component is AchievementsButton ||
          component is OpenMenuButton,
    )) {
      component.removeFromParent();
    }
    addAllButtons();
  }

  void removeControls() {
    if (children.any((component) => component is JoystickComponent)) {
      isJoystickAdded = false;
      customJoystick.joystick.removeFromParent();
    }
    for (var component in children.whereType<JumpButton>()) {
      component.removeFromParent();
    }
  }

  void addAllButtons() {
    if (changeSkinButton == null ||
        levelSelectionButton == null ||
        achievementsButton == null ||
        jumpButton == null ||
        menuButton == null) {
      initializateButtons();
    }
    changeSkinButton!.size = Vector2.all(settings.hudSize);
    achievementsButton!.size = Vector2.all(settings.hudSize);
    levelSelectionButton!.size = Vector2.all(settings.hudSize);
    menuButton!.size = Vector2.all(settings.hudSize);
    achievementsButton!.position = Vector2((settings.hudSize * 2) + 30, 10);
    changeSkinButton!.position = Vector2(settings.hudSize + 20, 10);
    levelSelectionButton!.position = Vector2(10, 10);
    addAll([
      changeSkinButton!,
      levelSelectionButton!,
      menuButton!,
      achievementsButton!
    ]);
    if (settings.showControls) {
      jumpButton!.size = Vector2.all(settings.controlSize * 2);
      add(jumpButton!);
      addJoystick();
    }
  }

  void updateGlobalStats() {
    if (gameData == null) return;
    gameData!.totalTime += level.levelTime;
    gameData!.totalDeaths += level.deathCount;
    levelTimes[gameData!.currentLevel] = level.levelTime;
    levelDeaths[gameData!.currentLevel] = level.deathCount;
  }

  void completeLevel() async {
    level.stopLevelTimer();

    updateGlobalStats();

    removeAudios();
    if (gameData != null) {
      final int currentLevel = gameData!.currentLevel + 1;
      GameLevel currentGameLevel =
      levels[currentLevel - 1]['gameLevel'] as GameLevel;

      levels[currentLevel - 1]['gameLevel'].stars = level.starsCollected;

      // Marcar el nivel como completado
      currentGameLevel.completed = true;
      currentGameLevel.time = level.levelTime;
      currentGameLevel.deaths = level.deathCount;
      print('Level $currentLevel marked as completed!');

      // Unlock the next level if exists
      if (currentLevel < levels.length) {
        GameLevel nextGameLevel = levels[currentLevel]['gameLevel'] as GameLevel;
        nextGameLevel.unlocked = true;
        print('Level ${currentLevel + 1} unlocked!');
        addLevelSummaryScreen();
      } else {
        await creditsScreen.show();
      }
    }

    await level.saveLevel();
  }

  void removeAudios() {
    try {
      for (final component in level.children) {
        if (component is FireBlock) {
          component.removeSound();
        }
      }
    } catch (e) {
      /// When the leves isn't initialized we dont remove sound
    }
  }

  void _loadActualLevel() async {
    final service = await GameService.getInstance();
    service.saveGameBySpace(game: gameData);
    removeAudios();
    removeWhere((component) => component is Level);
    if (settings.isMusicActive) {
      FlameAudio.bgm.stop();
      FlameAudio.bgm.play('background_music.mp3', volume: settings.musicVolume);
      print('Playing music with volume: ${settings}');
    } else {
      FlameAudio.bgm.stop();
    }
    level = Level(levelName: levels[gameData?.currentLevel ?? 0]['level'].name,
        player: player);

    cam = CameraComponent.withFixedResolution(
        world: level, width: 640, height: 368);

    cam.priority = 10;
    cam.viewfinder.anchor = Anchor.topLeft;
    addAll([cam, level]);
  }

  void evaluateAchievements() {
    achievementManager.evaluate();
  }

  void addJoystick() {
    if (!isJoystickAdded) {
      isJoystickAdded = true;
      customJoystick = CustomJoystick(
        controlSize: settings.controlSize,
        leftMargin: settings.isLeftHanded ? size.x - 32 -
            settings.controlSize * 2 : 32,
      );
      add(customJoystick);
    }
  }

  void selectedCharacterIndex(int index) {
    if (gameData == null) return;
    gameData!.currentCharacter = index;
    player.updateCharacter(characters[index]);
  }

  void openChangeCharacterMenu() {
    overlays.add(CharacterSelection.id);
    pauseEngine();
  }

  void openLevelSelectionMenu() {
    overlays.add(LevelSelectionMenu.id);
    pauseEngine();
  }

  void pauseGame() {
    overlays.add(PauseMenu.id);
    pauseEngine();
  }

  void switchHUDPosition() {
    if (!settings.showControls) return;
    reloadAllButtons();
  }

  removeBlackScreen() {
    deathScreen.removeBlackScreen();
  }

  addBlackScreen() {
    deathScreen.size = size;
    final gameDeaths = gameData?.totalDeaths ?? 0;
    deathScreen.addBlackScreen(gameDeaths + level.deathCount);
  }

  addLevelSummaryScreen() {
    changeLevelScreen = ChangeLevelScreen(
      onCollapseEnd: () {
        overlays.add('level_summary');
        removeWhere((component) => component is Level);
      },
      onExpandEnd: () {
        gameData!.currentLevel++;
        _loadActualLevel(); // o lo que uses para cargar el siguiente
      },
    );
    add(changeLevelScreen);
  }

  Future<void> getGameService() async {
    gameService ??= await GameService.getInstance();
  }

  Future<void> getLevelService() async {
    levelService ??= await LevelService.getInstance();
  }

  Future<void> getAchievementService() async {
    achievementService ??= await AchievementService.getInstance();
  }

  Future<void> getSettingsService() async {
    settingsService ??= await SettingsService.getInstance();
  }

  void lockWindowResize() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final double width = size.x;
      final double height = size.y;
      final Size fixedSize = Size(width, height);
      setWindowMinSize(fixedSize);
      setWindowMaxSize(fixedSize);
    }
  }

  void unlockWindowResize() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      setWindowMinSize(const Size(800, 600));
      setWindowMaxSize(Size.infinite);
    }
  }
}