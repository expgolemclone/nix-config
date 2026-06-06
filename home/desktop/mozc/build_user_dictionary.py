#!/usr/bin/env python3

import argparse
import importlib
import json
import pathlib
import re
import sys
import unicodedata


READING_RE = re.compile(r"^[ぁ-ゖゝゞゔー・]+$")
DISALLOWED_TEXT_CHARS = ("\t", "\r", "\n")
SUPPORTED_POS_NAMES = (
    "ABBREVIATION",
    "ADJECTIVE",
    "ADJECTIVE_VERBAL_NOUN",
    "ADVERB",
    "ALPHABET",
    "BA_GROUP1_VERB",
    "CONJUNCTION",
    "COUNTER_SUFFIX",
    "EMOTICON",
    "FAMILY_NAME",
    "FIRST_NAME",
    "FREE_STANDING_WORD",
    "GA_GROUP1_VERB",
    "GENERIC_SUFFIX",
    "GROUP2_VERB",
    "HA_GROUP1_VERB",
    "INTERJECTION",
    "KA_GROUP1_VERB",
    "KURU_GROUP3_VERB",
    "MA_GROUP1_VERB",
    "NA_GROUP1_VERB",
    "NOUN",
    "NUMBER",
    "ORGANIZATION_NAME",
    "PERSONAL_NAME",
    "PERSON_NAME_SUFFIX",
    "PLACE_NAME",
    "PLACE_NAME_SUFFIX",
    "PREFIX",
    "PRENOUN_ADJECTIVAL",
    "PROPER_NOUN",
    "PUNCTUATION",
    "RA_GROUP1_VERB",
    "RU_GROUP3_VERB",
    "SA_GROUP1_VERB",
    "SA_IRREGULAR_CONJUGATION_NOUN",
    "SENTENCE_ENDING_PARTICLE",
    "SUGGESTION_ONLY",
    "SUPPRESSION_WORD",
    "SURU_GROUP3_VERB",
    "SYMBOL",
    "TA_GROUP1_VERB",
    "WA_GROUP1_VERB",
    "ZURU_GROUP3_VERB",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--proto-dir", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def fail(message: str) -> None:
    raise SystemExit(message)


def validate_plain_text(field_name: str, value: str) -> None:
    if not isinstance(value, str):
        fail(f"{field_name} must be a string")

    if value == "":
        fail(f"{field_name} must not be empty")

    if any(char in value for char in DISALLOWED_TEXT_CHARS):
        fail(f"{field_name} must not contain tabs or newlines")


def normalize_reading(reading: str) -> str:
    normalized = unicodedata.normalize("NFKC", reading)
    chars = []

    for char in normalized:
        codepoint = ord(char)
        if 0x30A1 <= codepoint <= 0x30F6:
            chars.append(chr(codepoint - 0x60))
        else:
            chars.append(char)

    return "".join(chars)


def load_dictionary_definition(input_path: pathlib.Path) -> dict:
    try:
        data = json.loads(input_path.read_text())
    except json.JSONDecodeError as error:
        fail(f"failed to parse dictionary json: {error}")

    if not isinstance(data, dict):
        fail("dictionary definition must be an object")

    allowed_top_level_keys = {"dictionaryName", "entries"}
    unknown_keys = sorted(set(data) - allowed_top_level_keys)
    if unknown_keys:
        fail(f"unsupported top-level keys: {', '.join(unknown_keys)}")

    dictionary_name = data.get("dictionaryName")
    if dictionary_name != "personal":
        fail("dictionaryName must be exactly 'personal' in v1")

    entries = data.get("entries")
    if not isinstance(entries, list):
        fail("entries must be a list")

    return {"dictionaryName": dictionary_name, "entries": entries}


def main() -> None:
    args = parse_args()

    proto_dir = pathlib.Path(args.proto_dir)
    sys.path.insert(0, str(proto_dir))
    pb2 = importlib.import_module("user_dictionary_storage_pb2")

    definition = load_dictionary_definition(pathlib.Path(args.input))
    pos_enum = pb2.UserDictionary.Entry.DESCRIPTOR.fields_by_name["pos"].enum_type
    available_pos_names = set(pos_enum.values_by_name)
    missing_supported_pos_names = sorted(set(SUPPORTED_POS_NAMES) - available_pos_names)
    if missing_supported_pos_names:
        fail(
            "upstream proto is missing supported POS values: {values}".format(
                values=", ".join(missing_supported_pos_names)
            )
        )

    storage = pb2.UserDictionaryStorage()
    storage.storage_type = pb2.UserDictionaryStorage.SNAPSHOT

    dictionary = storage.dictionaries.add()
    dictionary.id = 1
    dictionary.enabled = True
    dictionary.name = definition["dictionaryName"]

    seen_entries = set()

    for index, raw_entry in enumerate(definition["entries"], start=1):
        if not isinstance(raw_entry, dict):
            fail(f"entries[{index}] must be an object")

        allowed_entry_keys = {"key", "value", "pos", "comment"}
        unknown_entry_keys = sorted(set(raw_entry) - allowed_entry_keys)
        if unknown_entry_keys:
            fail(
                "entries[{index}] has unsupported keys: {keys}".format(
                    index=index,
                    keys=", ".join(unknown_entry_keys),
                )
            )

        try:
            raw_key = raw_entry["key"]
            value = raw_entry["value"]
            pos_name = raw_entry["pos"]
        except KeyError as error:
            fail(f"entries[{index}] is missing required field: {error.args[0]}")

        comment = raw_entry.get("comment", "")
        validate_plain_text(f"entries[{index}].key", raw_key)
        validate_plain_text(f"entries[{index}].value", value)

        if not isinstance(comment, str):
            fail(f"entries[{index}].comment must be a string")
        if any(char in comment for char in DISALLOWED_TEXT_CHARS):
            fail(f"entries[{index}].comment must not contain tabs or newlines")

        if not isinstance(pos_name, str):
            fail(f"entries[{index}].pos must be a string")
        if pos_name not in SUPPORTED_POS_NAMES:
            fail(
                "entries[{index}].pos must be one of: {values}".format(
                    index=index,
                    values=", ".join(SUPPORTED_POS_NAMES),
                )
            )

        key = normalize_reading(raw_key)
        if not READING_RE.fullmatch(key):
            fail(
                f"entries[{index}].key must normalize to hiragana reading; got: {raw_key!r}"
            )

        dedupe_key = (key, value, pos_name)
        if dedupe_key in seen_entries:
            fail(
                f"entries[{index}] duplicates an earlier entry with the same key/value/pos"
            )
        seen_entries.add(dedupe_key)

        entry = dictionary.entries.add()
        entry.key = key
        entry.value = value
        entry.comment = comment
        entry.pos = pos_enum.values_by_name[pos_name].number

    pathlib.Path(args.output).write_bytes(storage.SerializeToString())


if __name__ == "__main__":
    main()
