#!/usr/bin/env python3
"""Records Mitra's guide lines with Sarvam's voices and saves them as clips
the app ships with (assets/voice/<lang>/<key>.mp3, listed in
assets/voice/manifest.json).

Only lines that are new or changed since the last run are recorded, so a
re-run costs nothing when nothing changed.

Run from fieldos_mobile/ with the key in the environment (never commit it):

    SARVAM_API_KEY=... python3 tool/guide_voice/make_clips.py [--only te,hi] [--dry-run]

Cost: Bulbul v4 Flash is about Rs 1 per 1,000 characters; the whole guide in
six languages is roughly 9,000 characters.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.request

API = 'https://api.sarvam.ai/text-to-speech'
MODEL = 'bulbul:v4-flash'
ROOT = os.path.join('assets', 'voice')
MANIFEST = os.path.join(ROOT, 'manifest.json')


def load_lines():
    out = subprocess.run(['dart', 'run', 'tool/guide_voice/dump_lines.dart'],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out.strip().splitlines()[-1])


def speak(key, text, lang, voice):
    body = json.dumps({
        'text': text,
        'language_code': f'{lang}-IN',
        'speaker': voice,
        'model': MODEL,
        'pace': 0.95,
        'speech_sample_rate': 24000,
        'output_audio_codec': 'mp3',
    }).encode()
    req = urllib.request.Request(API, data=body, method='POST', headers={
        'api-subscription-key': key, 'content-type': 'application/json'})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = json.load(r)
    return b''.join(base64.b64decode(a) for a in data['audios'])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', help='comma-separated language codes')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    data = load_lines()
    lines, voices = data['lines'], data['voices']
    only = set(args.only.split(',')) if args.only else None
    manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}

    todo = []
    for lang, entries in lines.items():
        if only and lang not in only:
            continue
        for k, text in entries.items():
            path = os.path.join(ROOT, lang, f'{k}.mp3')
            if manifest.get(lang, {}).get(k) == text and os.path.exists(path):
                continue
            todo.append((lang, k, text, path))

    chars = sum(len(t) for _, _, t, _ in todo)
    print(f'{len(todo)} clips to record, {chars} characters (about Rs {chars / 1000:.0f}).')
    if args.dry_run or not todo:
        return
    key = os.environ.get('SARVAM_API_KEY')
    if not key:
        sys.exit('Set SARVAM_API_KEY first.')

    for lang, k, text, path in todo:
        audio = speak(key, text, lang, voices[lang])
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(audio)
        manifest.setdefault(lang, {})[k] = text
        with open(MANIFEST, 'w') as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1, sort_keys=True)
        print(f'  {lang}/{k}.mp3  {len(audio) // 1024} KB')


if __name__ == '__main__':
    main()
