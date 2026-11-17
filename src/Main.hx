package mods.weapon_modifiers_in_inventory_preview;

import account.ItemInfo;
import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.SwfAsset;
import brain.stateMachine.State;
import brain.stateMachine.StateMachine;
import brain.uI.UIObject;
import facade.DBFacade;
import flash.display.DisplayObject;
import flash.geom.Point;
import flash.geom.Rectangle;
import haxe.Timer;
import mods.api.Context;
import mods.api.Mod;
import openfl.display.DisplayObjectContainer;
import openfl.display.Sprite;
import openfl.filters.DropShadowFilter;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import town.InventoryTownSubState;
import uI.inventory.UIInventory;
import uI.inventory.UIInventoryItem;

/** Shows each weapon's level and modifier icons on cards in the town inventory. */
@:privateAccess
class Main extends Mod {
	static inline final ROW_NAME:String = "weaponModifierIcons";
	static inline final WEAPON_LEVEL_NAME:String = "weaponLevelBadge";
	static inline final MODIFIER_ICONS_SWF:String = "Resources/Art2D/Icons/Modifier/db_icons_modifier.swf";
	static inline final ICON_CANVAS_SIZE:Float = 72;
	static inline final ICON_SIZE:Float = 18;
	static inline final BADGE_WIDTH:Float = 18;
	static inline final BADGE_HEIGHT:Float = 18;
	static inline final GAP:Float = 1;

	var context:Context;
	var town:InventoryTownSubState;
	var refreshTimer:Timer;
	var iconLoader:AssetLoadingComponent;
	var iconAsset:SwfAsset;
	var loadingIcons:Bool = false;

	override public function init(context:Context):Void {
		this.context = context;
		context.core.onStateEnter(function(_:StateMachine, state:State) {
			if (!Std.isOfType(state, InventoryTownSubState))
				return;
			town = cast state;
			// A low-rate refresh picks up page changes only while this inventory is open.
			refreshTimer = new Timer(250);
			refreshTimer.run = scanInventory;
			loadModifierIcons();
		});
		context.core.onStateExit(function(_:StateMachine, state:State) {
			if (state == town)
				stopRefresh();
		});
	}

	function scanInventory():Void {
		if (town == null || !context.core.alive)
			return;
		var inventory:UIInventory = town.mUIInventory;
		if (inventory == null || inventory.mItems == null)
			return;

		// Only the visible page's small card list is scanned, four times a second, in town.
		for (card in inventory.mItems) {
			if (card == null)
				continue;
			var root:DisplayObjectContainer = Std.downcast(card.root, DisplayObjectContainer);
			if (root == null)
				continue;
			var info:ItemInfo = Std.downcast(card.mInfo, ItemInfo);
			if (info == null || info.gmWeaponItem == null) {
				removeBadges(root);
				removeWeaponLevel(root);
				continue;
			}
			var iconBounds = card.mIcon == null ? root.getBounds(root) : fixedIconBounds(card.mIcon, root);
			drawWeaponLevel(root, info, 2, iconBounds);
			if (iconAsset != null)
				drawBadges(root, info, 0, iconBounds);
		}

		scanEquippedWeapons(inventory);
	}

	function scanEquippedWeapons(inventory:UIInventory):Void {
		if (inventory.mHeroWithEquipPicker == null || inventory.mHeroWithEquipPicker.mEquipElements == null)
			return;

		// The three persistent weapon slots at the bottom of the inventory/store screen.
		for (element in inventory.mHeroWithEquipPicker.mEquipElements) {
			if (element == null)
				continue;
			// Keep overlays on the outer slot so they stay above the asynchronously loaded art.
			var root:DisplayObjectContainer = Std.downcast(element.root, DisplayObjectContainer);
			if (root == null)
				continue;
			var info:ItemInfo = ASCompat.reinterpretAs(element.itemInfo, ItemInfo);
			if (info == null || info.gmWeaponItem == null) {
				removeBadges(root);
				removeWeaponLevel(root);
				continue;
			}
			var weaponArt:DisplayObject = element.mIcon;
			var slotFrame:DisplayObject = ASCompat.coerce((element.root : ASAny).frame, DisplayObject);
			var boundsSource:DisplayObject = weaponArt == null ? slotFrame : weaponArt;
			if (boundsSource == null)
				continue;
			var iconBounds = boundsSource.getBounds(root);
			// Use the fixed slot frame immediately, then switch to the weapon's actual
			// bounds as soon as its asynchronously loaded icon becomes available.
			drawWeaponLevel(root, info, -11, iconBounds);
			if (iconAsset != null)
				drawBadges(root, info, 0, iconBounds);
		}
	}

	function fixedIconBounds(icon:DisplayObject, root:DisplayObjectContainer):Rectangle {
		// The icon clip is centered on its registration point. Its normalized 72px canvas
		// and dynamic rarity background are both centered there; ignore the background bounds.
		var half = ICON_CANVAS_SIZE / 2;
		var topLeft = root.globalToLocal(icon.localToGlobal(new Point(-half, -half)));
		var bottomRight = root.globalToLocal(icon.localToGlobal(new Point(half, half)));
		var x = Math.min(topLeft.x, bottomRight.x);
		var y = Math.min(topLeft.y, bottomRight.y);
		return new Rectangle(x, y, Math.abs(bottomRight.x - topLeft.x), Math.abs(bottomRight.y - topLeft.y));
	}

	function drawWeaponLevel(root:DisplayObjectContainer, info:ItemInfo, topInset:Float = 11, bounds:Rectangle = null):Void {
		var level = Std.string(info.requiredLevel);
		if (bounds == null)
			bounds = root.getBounds(root);
		var old = findWeaponLevel(root);
		if (old != null && old.name == WEAPON_LEVEL_NAME + "|" + level) {
			old.x = bounds.x + 3;
			old.y = bounds.y + topInset;
			root.setChildIndex(old, root.numChildren - 1);
			return;
		}
		if (old != null)
			root.removeChild(old);

		var badge = new Sprite();
		badge.name = WEAPON_LEVEL_NAME + "|" + level;
		badge.mouseEnabled = false;
		badge.mouseChildren = false;
		badge.x = bounds.x + 3;
		badge.y = bounds.y + topInset;
		badge.graphics.lineStyle(1, 0xD4A641, 1);
		badge.graphics.beginFill(0x21130D, 0.94);
		badge.graphics.drawRoundRect(0, 0, 25, 12, 3, 3);
		badge.graphics.endFill();

		var text = new TextField();
		text.defaultTextFormat = new TextFormat("Arial", 8, 0xFFFFFF, true, null, null, null, null, "center");
		text.selectable = false;
		text.mouseEnabled = false;
		text.autoSize = TextFieldAutoSize.NONE;
		text.width = 25;
		text.height = 12;
		text.text = "L" + level;
		text.filters = [new DropShadowFilter(1, 90, 0x000000, 1, 1, 1, 3, 2)];
		badge.addChild(text);
		root.addChild(badge);
	}

	function drawBadges(root:DisplayObjectContainer, info:ItemInfo, bottomInset:Float = 12, bounds:Rectangle = null):Void {
		var badges:Array<BadgeData> = [];
		for (modifier in info.modifiers) {
			if (modifier == null)
				continue;
			var iconValue:Dynamic = Reflect.field(modifier, "IconName");
			var iconName:String = iconValue == null ? "" : Std.string(iconValue);
			if (iconName == "")
				continue;
			var nameValue:Dynamic = Reflect.field(modifier, "Name");
			var name:String = nameValue == null ? "Modifier" : Std.string(nameValue);
			var levelValue:Dynamic = Reflect.field(modifier, "MODIFIER_LEVEL");
			var level:Int = levelValue == null ? levelFromConstant(Std.string(Reflect.field(modifier, "Constant"))) : Std.int(levelValue);
			badges.push(new BadgeData(iconName, level > 0 ? Std.string(level) : "", name));
		}

		if (info.legendaryModifier > 0) {
			var legendary:Dynamic = null;
			try {
				legendary = context.core.facade.gameMaster.legendaryModifiersById.itemFor(info.legendaryModifier);
			} catch (error:Dynamic) {}
			if (legendary != null) {
				var iconValue:Dynamic = Reflect.field(legendary, "IconName");
				var iconName:String = iconValue == null ? "" : Std.string(iconValue);
				if (iconName != "")
					badges.push(new BadgeData(iconName, "", Std.string(Reflect.field(legendary, "Name"))));
			}
		}

		var signatureParts:Array<String> = [];
		for (badge in badges)
			signatureParts.push(badge.icon + ":" + badge.level + ":" + badge.name);
		var signature = signatureParts.join("|");
		var old = findBadges(root);
		if (badges.length == 0) {
			if (old != null)
				root.removeChild(old);
			return;
		}

		var count = badges.length;
		if (bounds == null)
			bounds = root.getBounds(root);
		var available = Math.max(BADGE_WIDTH, bounds.width - 4);
		var width = Math.min(BADGE_WIDTH, (available - (count - 1) * GAP) / count);
		var step = width + GAP;
		var total = count * width + (count - 1) * GAP;
		// Use local bounds so the row stays centered under the weapon art at every UI scale.
		var rowX = bounds.x + (bounds.width - total) / 2;
		var rowY = bounds.bottom - BADGE_HEIGHT - bottomInset;
		var layout = Std.int(Math.round(bounds.x * 10)) + ":" + Std.int(Math.round(bounds.y * 10)) + ":"
			+ Std.int(Math.round(bounds.width * 10)) + ":" + Std.int(Math.round(bounds.height * 10));
		var rowName = ROW_NAME + "|" + signature + "|" + layout;
		if (old != null && old.name == rowName) {
			old.x = rowX;
			old.y = rowY;
			// Keep the modifiers above the weapon art when its SWF loads after the badges.
			root.setChildIndex(old, root.numChildren - 1);
			return;
		}
		if (old != null)
			root.removeChild(old);

		var row = new Sprite();
		row.name = rowName;
		row.mouseEnabled = false;
		row.mouseChildren = false;
		row.x = rowX;
		row.y = rowY;

		for (i in 0...badges.length)
			badge(row, badges[i], i * step, width);
		root.addChild(row);
	}

	function badge(row:Sprite, data:BadgeData, x:Float, width:Float):Void {
		var iconClass:Dynamic = iconAsset == null ? null : iconAsset.getClass(data.icon);
		if (iconClass == null)
			return;
		var iconSize = Math.min(ICON_SIZE, width);
		var icon:DisplayObject = cast ASCompat.createInstance(iconClass, []);
		UIObject.scaleToFit(icon, iconSize);
		icon.x = x + iconSize / 2;
		icon.y = BADGE_HEIGHT / 2;
		icon.name = data.icon;
		row.addChild(icon);

		if (data.level == "")
			return;
		var levelWidth:Float = 13;
		var levelHeight:Float = 16;
		row.graphics.lineStyle(1, 0xD4A641, 1);
		row.graphics.beginFill(0x21130D, 0.96);
		row.graphics.drawRoundRect(x + iconSize - levelWidth, BADGE_HEIGHT - levelHeight, levelWidth, levelHeight, 2, 2);
		row.graphics.endFill();
		var numberX = x + iconSize - levelWidth;
		var numberY = BADGE_HEIGHT - levelHeight;
		var text = new TextField();
		text.name = data.name + " (level " + data.level + ")";
		text.defaultTextFormat = new TextFormat("Arial", 12, 0xFFFFFF, true, null, null, null, null, "center");
		text.selectable = false;
		text.mouseEnabled = false;
		text.autoSize = TextFieldAutoSize.NONE;
		text.width = levelWidth;
		text.height = levelHeight;
		text.x = numberX;
		text.y = numberY;
		text.text = data.level;
		text.filters = [new DropShadowFilter(2, 90, 0x000000, 1, 1, 1, 4, 2)];
		row.addChild(text);
	}

	function loadModifierIcons():Void {
		if (iconAsset != null || loadingIcons || context.core.facade == null)
			return;
		loadingIcons = true;
		iconLoader = new AssetLoadingComponent(context.core.facade);
		try {
			iconLoader.getSwfAsset(DBFacade.buildFullDownloadPath(MODIFIER_ICONS_SWF), function(asset:SwfAsset) {
				loadingIcons = false;
				if (town == null || !context.core.alive)
					return;
				iconAsset = asset;
				if (iconAsset == null) {
					context.log("modifier icon SWF could not be loaded");
					return;
				}
				scanInventory();
			});
		} catch (error:Dynamic) {
			loadingIcons = false;
			context.log("modifier icon load failed: " + Std.string(error));
		}
	}

	function removeBadges(root:DisplayObjectContainer):Void {
		var row = findBadges(root);
		if (row != null)
			root.removeChild(row);
	}

	function removeWeaponLevel(root:DisplayObjectContainer):Void {
		var badge = findWeaponLevel(root);
		if (badge != null)
			root.removeChild(badge);
	}

	function findWeaponLevel(root:DisplayObjectContainer):Sprite {
		for (i in 0...root.numChildren) {
			var child:Sprite = Std.downcast(root.getChildAt(i), Sprite);
			if (child != null && StringTools.startsWith(child.name, WEAPON_LEVEL_NAME + "|"))
				return child;
		}
		return null;
	}

	function findBadges(root:DisplayObjectContainer):Sprite {
		for (i in 0...root.numChildren) {
			var child:Sprite = Std.downcast(root.getChildAt(i), Sprite);
			if (child != null && StringTools.startsWith(child.name, ROW_NAME + "|"))
				return child;
		}
		return null;
	}

	function stopRefresh():Void {
		if (refreshTimer != null) {
			refreshTimer.stop();
			refreshTimer = null;
		}
		if (iconLoader != null)
			iconLoader.destroy();
		iconLoader = null;
		iconAsset = null;
		loadingIcons = false;
		town = null;
	}

	static function levelFromConstant(constant:String):Int {
		if (constant == null || constant.length < 3 || constant.charAt(constant.length - 2) != "_")
			return 0;
		var level = Std.parseInt(constant.charAt(constant.length - 1));
		return level == null ? 0 : level;
	}

	override public function dispose():Void {
		stopRefresh();
		context = null;
	}
}

private class BadgeData {
	public var icon:String;
	public var level:String;
	public var name:String;

	public function new(icon:String, level:String, name:String) {
		this.icon = icon;
		this.level = level;
		this.name = name;
	}
}

