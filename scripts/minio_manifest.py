#!/usr/bin/env python3
"""Manifeste et SHA-256 des objets de la zone RAW (MinIO).

Ce script :
  1. (optionnel) depose le fichier CSV ORIGINAL, sans aucune modification, dans MinIO
     (raw/originaux/csv_communes/<AAAA-MM-JJ>_<nom>, hors des dossiers lus par les sources S3) ;
  2. liste les objets du prefixe 'raw/' du bucket ;
  3. calcule le SHA-256 de chaque objet en le relisant dans MinIO ;
  4. ecrit data/manifestes/minio_raw_manifest.csv et .json.

Aucun secret n'est ecrit ni affiche : les identifiants sont lus dans compose/.env (non versionne)
ou dans les variables d'environnement MINIO_ROOT_USER / MINIO_ROOT_PASSWORD.

Exemples :
  python3 scripts/minio_manifest.py
  python3 scripts/minio_manifest.py --upload-original data/communes_france.csv
"""
import argparse, csv, hashlib, json, os, sys
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError


def read_env(path):
    values = {}
    p = Path(path)
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                values[k.strip()] = v.strip().strip('"').strip("'")
    return values


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_object(s3, bucket, key):
    h = hashlib.sha256()
    body = s3.get_object(Bucket=bucket, Key=key)["Body"]
    for chunk in iter(lambda: body.read(1024 * 1024), b""):
        h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--endpoint", default=os.environ.get("MINIO_ENDPOINT", "http://localhost:9000"))
    ap.add_argument("--bucket", default="dsid-raw")
    ap.add_argument("--prefix", default="raw/")
    ap.add_argument("--env-file", default="compose/.env")
    ap.add_argument("--upload-original", metavar="FICHIER_CSV",
                    help="depose ce fichier tel quel dans raw/originaux/csv_communes/ (nom de lot date)")
    ap.add_argument("--out-dir", default="data/manifestes")
    args = ap.parse_args()

    env = read_env(args.env_file)
    user = os.environ.get("MINIO_ROOT_USER") or env.get("MINIO_ROOT_USER")
    pwd = os.environ.get("MINIO_ROOT_PASSWORD") or env.get("MINIO_ROOT_PASSWORD")
    if not user or not pwd:
        sys.exit("Identifiants MinIO introuvables (compose/.env ou variables d'environnement).")

    s3 = boto3.client("s3", endpoint_url=args.endpoint, aws_access_key_id=user, aws_secret_access_key=pwd,
                      region_name="us-east-1", config=Config(signature_version="s3v4",
                                                             s3={"addressing_style": "path"}))

    # Controle du bucket : s'il n'existe pas, on prend le seul bucket present, sinon on liste les choix.
    buckets = [b["Name"] for b in s3.list_buckets().get("Buckets", [])]
    if args.bucket not in buckets:
        if len(buckets) == 1:
            print(f"Bucket '{args.bucket}' absent : utilisation du seul bucket present, '{buckets[0]}'.")
            args.bucket = buckets[0]
        else:
            sys.exit(f"Bucket '{args.bucket}' introuvable. Buckets presents : {buckets}. Relancer avec --bucket NOM.")

    if args.upload_original:
        src = Path(args.upload_original)
        if not src.is_file():
            sys.exit(f"Fichier introuvable : {src}")
        local_sha = sha256_file(src)
        day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        key = f"raw/originaux/csv_communes/{day}_{src.name}"
        try:
            s3.head_object(Bucket=args.bucket, Key=key)
            print(f"Deja present, non re-depose : {key}")
        except ClientError:
            s3.upload_file(str(src), args.bucket, key)
            print(f"Depose sans modification : {key}")
        remote_sha = sha256_object(s3, args.bucket, key)
        print(f"SHA-256 local  : {local_sha}\nSHA-256 MinIO  : {remote_sha}")
        if local_sha != remote_sha:
            sys.exit("ERREUR : le fichier dans MinIO differe du fichier local.")

    paginator = s3.get_paginator("list_objects_v2")

    def list_objects(prefix):
        found = []
        for page in paginator.paginate(Bucket=args.bucket, Prefix=prefix):
            found.extend(o for o in page.get("Contents", []) if not o["Key"].endswith("/"))
        return found

    objects = list_objects(args.prefix)
    if not objects and args.prefix:
        print(f"Aucun objet sous le prefixe '{args.prefix}' : inventaire du bucket entier.")
        args.prefix = ""
        objects = list_objects("")

    rows = []
    for obj in objects:
        rows.append({
            "bucket": args.bucket,
            "object_key": obj["Key"],
            "size_bytes": obj["Size"],
            "last_modified_utc": obj["LastModified"].astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "sha256": sha256_object(s3, args.bucket, obj["Key"]),
        })
    rows.sort(key=lambda r: r["object_key"])

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(out / "minio_raw_manifest.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else
                           ["bucket", "object_key", "size_bytes", "last_modified_utc", "sha256"])
        w.writeheader()
        w.writerows(rows)
    with open(out / "minio_raw_manifest.json", "w", encoding="utf-8") as f:
        json.dump({"generated_at_utc": generated, "bucket": args.bucket, "prefix": args.prefix,
                   "object_count": len(rows), "objects": rows}, f, ensure_ascii=False, indent=2)

    print(f"\n{len(rows)} objet(s) dans s3://{args.bucket}/{args.prefix}  (manifeste genere le {generated})")
    for r in rows:
        print(f"- {r['object_key']}\n    {r['size_bytes']} octets | {r['last_modified_utc']} | sha256 {r['sha256']}")


if __name__ == "__main__":
    main()
