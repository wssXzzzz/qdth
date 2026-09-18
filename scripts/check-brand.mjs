// Prevent the Home Screen, settings, and widget artwork from drifting apart.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const icon = fs.readFileSync(path.join(root,'Inkflow/Assets.xcassets/AppIcon.appiconset/AppIcon.png'));
const mark = fs.readFileSync(path.join(root,'BrandAssets.xcassets/BrandMark.imageset/BrandMark.png'));
assert.deepEqual(icon, mark, 'AppIcon and BrandMark must contain identical artwork');
assert.equal(icon.subarray(1,4).toString(), 'PNG');
assert.equal(icon.readUInt32BE(16), 1024, 'Icon width');
assert.equal(icon.readUInt32BE(20), 1024, 'Icon height');
assert.equal(icon[25], 2, 'App icon must be opaque RGB, not RGBA');

const {objects} = JSON.parse(execFileSync('plutil', ['-convert','json','-o','-',path.join(root,'Inkflow.xcodeproj/project.pbxproj')]));
for (const name of ['Inkflow','InkflowLocal','InkflowWidget','InkflowLocalWidget']) {
    const target = Object.values(objects).find(o => o.isa === 'PBXNativeTarget' && o.name === name);
    assert.ok(target, `Missing target ${name}`);
    const files = target.buildPhases.flatMap(id => objects[id].files ?? [])
        .map(id => objects[objects[id].fileRef]?.path);
    assert.ok(files.includes('BrandAssets.xcassets'), `${name} must bundle the shared artwork`);
    assert.ok(files.includes('Inkflow/App/InkflowMark.swift'), `${name} must use the shared mark view`);
}
console.log('Brand checks passed: identical opaque 1024px artwork, included in all four targets.');
