"""
Script di migrazione dati da CoreData (SQLite locale) a Postgres cloud

Uso:
    python scripts/migrate_from_coredata.py --sqlite-path /path/to/PerX.sqlite --postgres-url postgresql://...
"""
import argparse
import sqlite3
import asyncio
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional

import asyncpg
from app.core.config import settings


async def migrate_claims(
    sqlite_conn: sqlite3.Connection,
    pg_pool: asyncpg.Pool,
    tenant_id: str
):
    """Migra sinistri da SQLite a Postgres"""
    
    # Leggi sinistri da SQLite
    cursor = sqlite_conn.cursor()
    cursor.execute("""
        SELECT 
            Z_PK, ZRIFERIMENTO, ZSTATO, ZNUMEROSINISTROCOMPAGNIA, ZNOMECOMPAGNIA,
            ZAGENZIA, ZCODICEAGENZIA, ZEMAILAGENZIA, ZTELEFONOAGENZIA,
            ZNOMEASSICURATO, ZEMAILASSICURATO, ZTELEFONOASSICURATO, ZINDIRIZZOASSICURATO,
            ZNOMECONTRAENTE, ZEMAILCONTRAENTE, ZTELEFONOCONTRAENTE, ZINDIRIZZOCONTRAENTE,
            ZNOMEDANNEGGIATO, ZEMAILDANNEGGIATO, ZTELEFONODANNEGGIATO, ZINDIRIZZODANNEGGIATO,
            ZDATASINISTRO, ZDATADENUNCIA, ZDATAINCARICO, ZDATAAPERTURAGESTIONE,
            ZDATAASSEGNAZIONE, ZDATAINVIOATTO, ZDATARITORNOATTO, ZDATACHIUSURA,
            ZDATAREVOCA, ZDATASOPRALLUOGO,
            ZRICHIESTA, ZLIQUIDATO, ZDANNOACCERTATO, ZDANNOACCERTATONETTO, ZSTIMADANNO,
            ZNUMEROPOLIZZA, ZTIPOPOLIZZA, ZDIVISIONECOMPAGNIA,
            ZIBAN, ZSINISTROCOLLEGATO, ZIDSINISTROCOLLEGATO, ZSOPRALLUOGO,
            ZGIUSTIFICATIVI, ZFOTO, ZOLTREDIECIBENI, ZCONCORDATA, ZNEGATIVA,
            ZUBICAZIONEVALIDATA, ZUBICAZIONENOTE,
            ZFULMINAZIONE, ZGRUPPO, ZAREA, ZCOMPLESSITA, ZDEFINIZIONE, ZPROPENSIONEPERITO,
            ZCARTELLA, ZOWNEREMAIL, ZDATACREAZIONE
        FROM ZSINISTRO
    """)
    
    rows = cursor.fetchall()
    print(f"Trovati {len(rows)} sinistri da migrare")
    
    migrated = 0
    errors = 0
    
    async with pg_pool.acquire() as conn:
        for row in rows:
            try:
                # Mappa i campi (adatta i nomi colonne SQLite al tuo schema CoreData)
                claim_id = str(uuid.uuid4())
                external_ref = row[1]  # ZRIFERIMENTO
                # ZSTATO è ancora un codice SV legacy nel CoreData sorgente;
                # convertiamo allo slug canonico (default: istruzione).
                from app.core.claim_status import LEGACY_SV_TO_SLUG, ClaimStatus
                _raw_stato = row[2] or "SV001"
                _mapping = LEGACY_SV_TO_SLUG.get(_raw_stato)
                stato = _mapping[0] if _mapping else ClaimStatus.ISTRUZIONE.value
                
                # Converti date
                def parse_date(val):
                    if val:
                        try:
                            return datetime.fromtimestamp(val) if isinstance(val, (int, float)) else val
                        except:
                            return None
                    return None
                
                # Converti decimali
                def parse_decimal(val):
                    if val is not None:
                        try:
                            return Decimal(str(val))
                        except:
                            return None
                    return None
                
                # Inserisci in Postgres
                await conn.execute("""
                    INSERT INTO claims (
                        id, tenant_id, external_ref, numero_sinistro, compagnia,
                        stato_corrente, agenzia, codice_agenzia, email_agenzia, telefono_agenzia,
                        nome_assicurato, email_assicurato, telefono_assicurato, indirizzo_assicurato,
                        nome_contraente, email_contraente, telefono_contraente, indirizzo_contraente,
                        nome_danneggiato, email_danneggiato, telefono_danneggiato, indirizzo_danneggiato,
                        data_sinistro, data_denuncia, data_incarico, data_apertura_gestione,
                        data_assegnazione, data_invio_atto, data_ritorno_atto, closed_at,
                        data_revoca, data_sopralluogo,
                        richiesta, liquidato, danno_accertato, danno_accertato_netto, stima_danno,
                        numero_polizza, tipo_polizza, divisione_compagnia,
                        iban, sinistro_collegato, id_sinistro_collegato, sopralluogo,
                        giustificativi, foto, oltre_dieci_beni, concordata, negativa,
                        ubicazione_validata, ubicazione_note,
                        fulminazione, gruppo, area, complessita, definizione, propensione_perito,
                        cartella, owner_email, created_at, version, priority
                    ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                        $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
                        $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
                        $31, $32, $33, $34, $35, $36, $37, $38, $39, $40,
                        $41, $42, $43, $44, $45, $46, $47, $48, $49, $50,
                        $51, $52, $53, $54, $55, $56, $57, $58, $59, $60
                    )
                """,
                    claim_id, tenant_id, external_ref, row[3], row[4],  # id, tenant, ref, numero, compagnia
                    stato, row[5], row[6], row[7], row[8],  # stato, agenzia, codice, email, telefono
                    row[9], row[10], row[11], row[12],  # nome_assicurato, email, telefono, indirizzo
                    row[13], row[14], row[15], row[16],  # contraente
                    row[17], row[18], row[19], row[20],  # danneggiato
                    parse_date(row[21]), parse_date(row[22]), parse_date(row[23]), parse_date(row[24]),  # date sinistro, denuncia, incarico, apertura
                    parse_date(row[25]), parse_date(row[26]), parse_date(row[27]), parse_date(row[28]),  # assegnazione, invio, ritorno, chiusura
                    parse_date(row[29]), parse_date(row[30]),  # revoca, sopralluogo
                    parse_decimal(row[31]), parse_decimal(row[32]), parse_decimal(row[33]), parse_decimal(row[34]), parse_decimal(row[35]),  # finanziari
                    row[36], row[37], row[38],  # polizza
                    bool(row[39]), bool(row[40]), row[41], bool(row[42]),  # flags
                    bool(row[43]), bool(row[44]), bool(row[45]), bool(row[46]), bool(row[47]),  # flags
                    bool(row[48]), row[49],  # ubicazione
                    row[50], row[51], row[52], row[53], row[54], row[55],  # classificazione
                    row[56], row[57], parse_date(row[58]) or datetime.utcnow(),  # cartella, owner, created
                    1, 0  # version, priority
                )
                
                migrated += 1
                if migrated % 100 == 0:
                    print(f"Migrati {migrated} sinistri...")
                    
            except Exception as e:
                errors += 1
                print(f"Errore migrazione sinistro {row[1]}: {e}")
    
    print(f"Migrazione completata: {migrated} sinistri, {errors} errori")


async def main():
    parser = argparse.ArgumentParser(description="Migra dati da CoreData SQLite a Postgres")
    parser.add_argument("--sqlite-path", required=True, help="Path al file SQLite CoreData")
    parser.add_argument("--postgres-url", required=True, help="URL connessione Postgres")
    parser.add_argument("--tenant-id", required=True, help="ID tenant di destinazione")
    
    args = parser.parse_args()
    
    # Connetti a SQLite
    sqlite_conn = sqlite3.connect(args.sqlite_path)
    
    # Connetti a Postgres
    pg_pool = await asyncpg.create_pool(args.postgres_url)
    
    try:
        await migrate_claims(sqlite_conn, pg_pool, args.tenant_id)
    finally:
        sqlite_conn.close()
        await pg_pool.close()


if __name__ == "__main__":
    asyncio.run(main())

