import haxe.ds.StringMap;
import backend.Rating;
import flixel.group.FlxTypedGroup;
import objects.NoteSplash;
import objects.PixelSplashShaderRef;
import objects.StrumNote;
import psychlua.ModchartSprite;
import shaders.RGBPalette;

var holdCovers:FlxTypedGroup<ModchartSprite>;
var coverTimers:Array<FlxTimer> = [];

var noSplashWhenSpawn:Bool = getModSetting('noSplashWhenCoverSpawn');
var loopHolds:Bool = getModSetting('loopHoldAnim');
var sicksOnly:Bool = getModSetting('sicksOnly');
var oppoHasHoldsOnly = function(?isPlayer:Bool = false):Bool {
	if (isPlayer == null) isPlayer = false;
	return getModSetting('opponentOnlyHasHoldAnim') && (!isPlayer || (getModSetting('botplayHasEndSplash') ? false : game.cpuControlled));
}

function setupTimer(cover:ModchartSprite, ?customDur:Float):{cover:ModchartSprite, timer:FlxTimer} {
	var timer:FlxTimer;
	coverTimers.push(timer = new FlxTimer().start(customDur == null ? (Conductor.stepCrochet / 1000) : customDur, (_:FlxTimer) -> {
		coverTimers.remove(timer);
		if (cover.animation.name != 'end')
			coverAnim(cover, 'end', true);
	}));
	return {cover: cover, timer: timer}
}

var animCheck:StringMap<ModchartSprite->Bool> = [
	'start' => (cover:ModchartSprite) -> return cover.animation.name == null,
	'hold' => (cover:ModchartSprite) -> return cover.animation.name == 'start',
	'end' => (cover:ModchartSprite) -> return cover.animation.name == 'hold'
];
function coverAnim(cover:ModchartSprite, name:String, ?force:Bool = false) {
	if (cover.animOffsets.exists(name) && animCheck.exists(name) ? (force ? true : animCheck.get(name)(cover)) : true) {
		cover.playAnim(name, true);
	}
}

function setupCover(lol:ModchartSprite, noteData:Int):ModchartSprite {
	var cover:ModchartSprite = lol;
	if (cover == null) cover = new ModchartSprite();
	var dir:String = noteData == null ? 'RGB' : ['Purple', 'Blue', 'Green', 'Red'][noteData % 4]; // jic
	cover.frames = Paths.getSparrowAtlas('holdCovers');
	cover.animation.addByPrefix('start', 'holdCoverStart' + dir, 24, false); cover.addOffset('start', -122, -125);
	cover.animation.addByPrefix('hold', 'holdCover' + dir, 24, true); cover.addOffset('hold', -97, -105);
	cover.animation.addByPrefix('end', 'holdCoverEnd' + dir, 24, false); cover.addOffset('end', -54, -77);
	cover.playAnim('start', true);
	cover.animation.finishCallback = (name:String) -> {
		switch (name) {
			case 'start': coverAnim(cover, 'hold');
			case 'end': cover.kill();
		}
	}
	return cover;
}

function onCreatePost() {
	holdCovers = new FlxTypedGroup();
	holdCovers.add(setupCover(null, null));
	setupTimer(holdCovers.members[0]).cover.alpha = 0.0001;
	game.noteGroup.insert(game.noteGroup.members.indexOf(game.grpNoteSplashes), holdCovers);
	return;
}

var sharedNoteHitPre:Note->Void = (note:Note) -> {
	final parent:Note = note.parent == null ? note : note.parent;
	var rating:Rating = Conductor.judgeNote(ratingsData, Math.abs(parent.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset) / playbackRate);
	if (sicksOnly ? rating.name == 'sick' : true || !note.mustPress) {
		if (!note.isSustainNote)
			if (note.sustainLength > 0)
				if (noSplashWhenSpawn)
					note.noteSplashData.disabled = true;
	}
}
function opponentNoteHitPre(note:Note) {sharedNoteHitPre(note); return;}
function goodNoteHitPre(note:Note) {sharedNoteHitPre(note); return;}
function otherStrumHitPre(note:Note, strumLane) {sharedNoteHitPre(note); return;}

var sharedNoteHit:Note->Void = (note:Note) -> {
	final parent:Note = note.parent == null ? note : note.parent;
	if (sicksOnly ? parent.rating == 'sick' : true || !note.mustPress) {
		if (!note.isSustainNote) {
			if (note.sustainLength > 0) {
				var cover:ModchartSprite;
				final colorSplash:Bool = note.noteSplashData.useRGBShader || !PlayState.SONG.disableNoteRGB;
				note.extraData.set('holdCover', setupTimer(setupCover(cover = holdCovers.recycle(ModchartSprite), colorSplash ? null : note.noteData), note.sustainLength / 1000).cover);
				holdCovers.add(cover);
				if (colorSplash) {
					var tempShader:RGBPalette = null;
					final rgbShader:PixelSplashShaderRef = new PixelSplashShaderRef();
					cover.shader = rgbShader.shader;
					if (!note.noteSplashData.useGlobalShader) {
						tempShader = new RGBPalette();
						tempShader.r = note.rgbShader.r;
						tempShader.g = note.rgbShader.g;
						tempShader.b = note.rgbShader.b;
					} else tempShader = Note.globalRgbShaders[note.noteData];
					rgbShader.copyValues(tempShader);
					cover.antialiasing = note.noteSplashData.antialiasing;
					if (PlayState.isPixelStage || !ClientPrefs.data.antialiasing) cover.antialiasing = false;
				}
				cover.alpha = ClientPrefs.data.splashAlpha;
				var strumGroup:FlxTypedGroup<StrumNote> = note.extraData.exists('setStrumLane') ? note.extraData.get('setStrumLane').lane : (note.mustPress ? game.playerStrums : game.opponentStrums);
				var strum:StrumNote = strumGroup.members[note.noteData];
				if (note != null) cover.alpha = note.noteSplashData.a * strum.alpha;
				coverAnim(cover, oppoHasHoldsOnly(note.mustPress) ? 'hold' : 'start', oppoHasHoldsOnly(note.mustPress)); // jic
				setCoverPos(cover, note.noteData, note.extraData.exists('setStrumLane') ? note.extraData.get('setStrumLane').lane : (note.mustPress ? game.playerStrums : game.opponentStrums)); // jic
			}
		} else {
			if (parent.extraData.exists('holdCover') && parent.extraData.get('holdCover') != null) {
				final cover:ModchartSprite = parent.extraData.get('holdCover');
				if (cover.animation.name == 'hold') {
					if (loopHolds) coverAnim(cover, 'hold', true);
					if (StringTools.endsWith(note.animation.name, 'end')) coverAnim(cover, 'end');
				}
			}
		}
	}
}
function opponentNoteHit(note:Note) {sharedNoteHit(note); return;}
function goodNoteHit(note:Note) {sharedNoteHit(note); return;}
function otherStrumHit(note:Note, strumLane) {sharedNoteHit(note); return;}

function noteMiss(note:Note) {
	var parent:Note = note.parent == null ? note : note.parent;
	if (parent.extraData.exists('holdCover') && parent.extraData.get('holdCover') != null)
		parent.extraData.get('holdCover').kill();
	return;
}

function setCoverPos(cover:ModchartSprite, data:Int, strumGroup:FlxTypedGroup<StrumNote>) {
	var strum:StrumNote = strumGroup.members[data];
	cover.setPosition(strum.x - Note.swagWidth * 0.95 - 13, strum.y - Note.swagWidth - 13);
}

function onUpdatePost(elapsed:Float) {
	for (timer in coverTimers)
		if (timer != null)
			timer.active = !paused;
	for (note in notes) {
		var parent:Note = note.parent == null ? note : note.parent;
		if (parent.extraData.exists('holdCover') && parent.extraData.get('holdCover') != null) {
			var cover:ModchartSprite = parent.extraData.get('holdCover');
			var strumGroup:FlxTypedGroup<StrumNote> = note.extraData.exists('setStrumLane') ? note.extraData.get('setStrumLane').lane : (note.mustPress ? game.playerStrums : game.opponentStrums);
			var strum:StrumNote = strumGroup.members[note.noteData];
			if (oppoHasHoldsOnly(note.mustPress) && cover.animation.name == 'end') cover.kill();
			if (cover.animation.name != 'end') setCoverPos(cover, note.noteData, strumGroup);
			cover.cameras = strum._cameras;
		}
	}
	return;
}