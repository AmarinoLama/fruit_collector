import 'dart:async';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:fruit_collector/components/game/content/traps/spike.dart';
import 'package:fruit_collector/components/game/util/custom_hitbox.dart';
import 'package:fruit_collector/components/game/level/sound_manager.dart';
import 'package:fruit_collector/components/game/content/blocks/loot_box.dart';
import 'package:fruit_collector/pixel_adventure.dart';

import '../../content/blocks/alterning_block.dart';
import '../../content/blocks/collision_block.dart';
import '../../content/blocks/falling_block.dart';
import '../../content/blocks/trampoline.dart';
import '../../level/level.dart';
import '../../util/utils.dart';
import '../enemies/chicken.dart';
import '../levelExtras/key_unlocker.dart';
import '../traps/fan/fan.dart';
import '../traps/saw.dart';
import 'checkpoint.dart';
import 'fruit.dart';

enum PlayerState {
  idle,
  running,
  jumping,
  double_jumping,
  falling,
  hit,
  appearing,
  disappearing,
  wallSlide,
}

class Player extends SpriteAnimationGroupComponent
    with HasGameReference<PixelAdventure>, KeyboardHandler, CollisionCallbacks {
  // Constructor and atributes
  String character;

  Player({super.position, this.character = 'Ninja Frog'});

  // Animations config
  late SpriteAnimation idleAnimation;
  late SpriteAnimation runningAnimation;
  late SpriteAnimation jumpingAnimation;
  late SpriteAnimation fallingAnimation;
  late SpriteAnimation hitAnimation;
  late SpriteAnimation appearingAnimation;
  late SpriteAnimation disappearingAnimation;
  late SpriteAnimation doubleJumpingAnimation;
  late SpriteAnimation wallSlideAnimation;
  final double stepTime = 0.05;

  // Movement logic
  final double _gravity = 9.8;
  double _jumpForce = 240;
  final double _maximunVelocity = 1000;
  final double _terminalVelocity = 300;
  double moveSpeed = 100;
  bool hasReached = false;
  double horizontalMovement = 0;
  Vector2 statringPosition = Vector2.zero();
  Vector2 velocity = Vector2.zero();
  bool isOnGround = false;
  bool isOnSand = false;
  bool hasJumped = false;
  int jumpCount = 0;
  double fixedDeltaTime = 1 / 60;
  double accumulatedTime = 0;

  // Double jump logic
  bool hasDoubleJumped = false;
  static const maxJumps = 2;

  // Death logic
  bool gotHit = false;
  bool isRespawning = false;

  // Key pressed logic
  bool isLeftKeyPressed = false;
  bool isRightKeyPressed = false;

  // Collision logic
  List<CollisionBlock> collisionBlocks = [];
  CustomHitbox hitbox = CustomHitbox(
    offsetX: 10,
    offsetY: 4,
    width: 14,
    height: 28,
  );

  @override
  FutureOr<void> onLoad() {
    _loadAllAnimations();
    //debugMode = true;
    statringPosition = Vector2(position.x, position.y);
    add(
      RectangleHitbox(
        position: Vector2(hitbox.offsetX, hitbox.offsetY),
        size: Vector2(hitbox.width, hitbox.height),
      ),
    );
    _animationRespawn();
    return super.onLoad();
  }

  @override
  void update(double dt) {
    accumulatedTime += dt;
    while (accumulatedTime >= fixedDeltaTime) {
      if (!gotHit && !hasReached) {
        if (isOnSand) {
          priority = -1;
        }
        _updatePlayerState();
        _updatePlayerMovement(fixedDeltaTime);
        _checkHorizontalCollisions();
        _applyGravity(fixedDeltaTime);
        _checkVerticalCollisions();
      }
      accumulatedTime -= fixedDeltaTime;
    }

    super.update(dt);
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    horizontalMovement = 0;
    isLeftKeyPressed =
        keysPressed.contains(LogicalKeyboardKey.keyA) ||
        keysPressed.contains(LogicalKeyboardKey.arrowLeft);
    isRightKeyPressed =
        keysPressed.contains(LogicalKeyboardKey.keyD) ||
        keysPressed.contains(LogicalKeyboardKey.arrowRight);

    horizontalMovement += isLeftKeyPressed ? -1 : 0;
    horizontalMovement += isRightKeyPressed ? 1 : 0;

    hasJumped =
        keysPressed.contains(LogicalKeyboardKey.space) ||
        keysPressed.contains(LogicalKeyboardKey.arrowUp);

    return super.onKeyEvent(event, keysPressed);
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    if (!hasReached) {
      if (other is Fruit) other.collidedWithPlayer();
      if (other is Saw) _respawn();
      if (other is Checkpoint && !hasReached) _reachedCheckpoint(other);
      if (other is Chicken) other.collidedWithPlayer();
      if (other is Trampoline) other.collidedWithPlayer();
      if (other is LootBox) other.collidedWithPlayer();
      if (other is KeyUnlocker) other.collidedWithPlayer();
    }
    super.onCollisionStart(intersectionPoints, other);
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    if (!hasReached) {
      if (other is Fan) other.collidedWithPlayer();
    }
    super.onCollision(intersectionPoints, other);
  }

  void _loadAllAnimations() {
    idleAnimation = _spriteAnimation('Idle', 11);
    runningAnimation = _spriteAnimation('Run', 12);
    jumpingAnimation = _spriteAnimation('Jump', 1);
    fallingAnimation = _spriteAnimation('Fall', 1);
    hitAnimation = _spriteAnimation('Hit', 7)..loop = false;
    appearingAnimation = _specialspriteAnimation('Appearing', 7);
    disappearingAnimation = _specialspriteAnimation('Desappearing', 7);
    doubleJumpingAnimation = _spriteAnimation('Double Jump', 6);
    wallSlideAnimation = _spriteAnimation('Wall Jump', 5);

    // List of all animations
    animations = {
      PlayerState.idle: idleAnimation,
      PlayerState.running: runningAnimation,
      PlayerState.jumping: jumpingAnimation,
      PlayerState.falling: fallingAnimation,
      PlayerState.hit: hitAnimation,
      PlayerState.appearing: appearingAnimation,
      PlayerState.disappearing: disappearingAnimation,
      PlayerState.double_jumping: doubleJumpingAnimation,
      PlayerState.wallSlide: wallSlideAnimation,
    };

    // Current animation
    current = PlayerState.idle;
  }

  SpriteAnimation _spriteAnimation(String state, int amount) {
    return SpriteAnimation.fromFrameData(
      game.images.fromCache('Main Characters/$character/$state.png'),
      SpriteAnimationData.sequenced(
        amount: amount,
        stepTime: stepTime,
        textureSize: Vector2.all(32),
      ),
    );
  }

  SpriteAnimation _specialspriteAnimation(String state, int amount) {
    return SpriteAnimation.fromFrameData(
      game.images.fromCache('Main Characters/$state (96x96).png'),
      SpriteAnimationData.sequenced(
        amount: amount,
        stepTime: stepTime,
        textureSize: Vector2.all(96),
        loop: false,
      ),
    );
  }

  void _updatePlayerMovement(double dt) {
    if (hasJumped && jumpCount < maxJumps) {
      _playerJump(dt);
    }
    // If you dont want to jump in the air, then:
    if (velocity.y > _gravity) isOnGround = false;
    velocity.x = horizontalMovement * moveSpeed;
    position.x += velocity.x * dt;
  }

  void _playerJump(double dt) {
    if (game.isGameSoundsActive) SoundManager().playJump(game.gameSoundVolume);

    jumpCount++;
    velocity.y = jumpCount == 2 ? -_jumpForce * 0.8 : -_jumpForce;
    isOnGround = false;
    hasJumped = false;
  }

  void _updatePlayerState() {
    PlayerState playerState = PlayerState.idle;

    if (velocity.x < 0 && scale.x > 0) {
      flipHorizontallyAroundCenter();
    } else if (velocity.x > 0 && scale.x < 0) {
      flipHorizontallyAroundCenter();
    }

    if (velocity.x != 0) {
      playerState = PlayerState.running;
    }

    if (velocity.y > 0) playerState = PlayerState.falling;

    if (velocity.y < 0 && jumpCount < 2) playerState = PlayerState.jumping;

    if (jumpCount == 2 && !isOnSand && !isRespawning)
      playerState = PlayerState.double_jumping;

    current = playerState;
  }

  void _checkHorizontalCollisions() {
    for (final block in collisionBlocks) {
      if (block is AlternatingBlock) {
        if (!block.isActive) {
          continue;
        }
      }
      if (!block.isPlatform) {
        if (checkCollision(this, block)) {
          if (velocity.x > 0) {
            velocity.x = 0;
            position.x = block.x - hitbox.offsetX - hitbox.width;
          }
          if (velocity.x < 0) {
            velocity.x = 0;
            position.x = block.x + block.width + hitbox.width + hitbox.offsetX;
          }
          _checkWallSlide(block);
        }
      }
    }
  }

  _checkWallSlide(CollisionBlock block) {
    if (velocity.y >= 0 && !isOnGround) {
      velocity.y = velocity.y * 0.7;
      current = PlayerState.wallSlide;
    }
  }

  void _applyGravity(double dt) {
    velocity.y += _gravity;
    velocity.y = velocity.y.clamp(-_maximunVelocity, _terminalVelocity);
    position.y += velocity.y * dt;
  }

  void _checkVerticalCollisions() {
    for (final block in collisionBlocks) {
      if (block is AlternatingBlock) {
        if (!block.isActive) {
          continue;
        }
      }
      /// TODO make that with downKey you can pass through the platforms
      if (block.isPlatform) {
        if (checkCollision(this, block)) {
          if (velocity.y > 0) {
            isOnGround = true;
            jumpCount = 0;
            velocity.y = 0;
            if (block is FallingBlock && !block.isFalling) {
              position.y = block.position.y - hitbox.height - hitbox.offsetY;
              if (block.isFalling) {
                position.y += block.fallingVelocity.y * fixedDeltaTime;
              }
            } else {
              position.y = block.y - hitbox.height - hitbox.offsetY;
            }
            break;
          }
        }

      } else if (block.isSand) {
        if (checkCollision(this, block)) {
          if (velocity.y > 0) {
            velocity.y = 0;
            moveSpeed = 0;
            _jumpForce = 0;
            current = PlayerState.falling;
          }
          isOnSand = true;
          break;
        }
      } else {
        if (checkCollision(this, block)) {
          if (velocity.y > 0) {
            velocity.y = 0;
            position.y = block.y - hitbox.height - hitbox.offsetY;
            isOnGround = true;
            jumpCount = 0;
            break;
          }
          if (velocity.y < 0) {
            current = PlayerState.wallSlide;
            velocity.y = 0;
            position.y = block.y + block.height - hitbox.offsetY;
            break;
          }
        }
      }
    }
  }

  void _respawn() async {
    if (isRespawning) {
      return;
    }
    isRespawning = true;
    if (game.isGameSoundsActive) SoundManager().playHit(game.gameSoundVolume);
    const inmobileDuration = Duration(milliseconds: 400);
    gotHit = true;
    isOnSand = false;
    current = PlayerState.hit;

    await _animationRespawn();

    game.children.query<Level>().first.respawnObjects();

    velocity = Vector2.zero();
    position = statringPosition;
    _updatePlayerState();
    Future.delayed(inmobileDuration, () => gotHit = false);
    _jumpForce = 260;
    moveSpeed = 100;
    isRespawning = false;
  }

  Future<void> _animationRespawn() async {
    await animationTicker?.completed;
    animationTicker?.reset();
    scale.x = 1;
    position = statringPosition - Vector2.all(32);
    current = PlayerState.appearing;

    await animationTicker?.completed;
    animationTicker?.reset();
  }

  void _reachedCheckpoint(Checkpoint other) async {
    if (!other.isAbled) {
      return;
    }
    if (game.isGameSoundsActive)
      SoundManager().playDisappear(game.gameSoundVolume);

    hasReached = true;
    if (scale.x > 0) {
      position = position - Vector2.all(32);
    } else if (scale.x < 0) {
      position = position + Vector2(32, -32);
    }
    current = PlayerState.disappearing;

    await animationTicker?.completed;
    animationTicker?.reset();
    hasReached = false;
    position = Vector2.all(-640);

    const waitToChangeDuration = Duration(seconds: 3);
    Future.delayed(waitToChangeDuration, () => game.loadNextLevel());
  }

  void collidedWithEnemy() {
    _respawn();
  }

  void updateCharacter(String newCharacter) {
    character = newCharacter;

    // Reload animations of the player
    _loadAllAnimations();
  }
}
