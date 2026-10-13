# Docker

```bash
docker build -t mab-governance -f docker/Dockerfile .
# synthetic demonstration (no data access needed)
docker run --rm -e DATA_MODE=synthetic -v "$PWD/outputs:/work/outputs" mab-governance
# real run: mount a credentialed MIMIC-IV v3.1 copy read only
docker run --rm -v /path/to/mimic-iv-3.1:/data/mimic-iv-3.1:ro -v "$PWD/outputs:/work/outputs" mab-governance
```
The container never copies MIMIC-IV data; it reads the mounted csv.gz files through DuckDB.
