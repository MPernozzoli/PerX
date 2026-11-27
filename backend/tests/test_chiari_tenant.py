from decimal import Decimal

from app.domain.chiari_import import map_claim, summarize
from app.domain.chiari_rules import extract_dated_rules
from app.domain.chiari_stima import hash_economico, workflow_reclaim
from app.domain.regia_invariants import iban_mod97_ok, iban_richiede_questione, liquidabile_consentito
from app.domain.tenant_capabilities import allows, apply_profile_locks, capabilities_for, chiari_settings


def test_chiari_profile_locks_outward_functions():
    settings = chiari_settings(allowed_domains=["chiarisrl.it"], internal_emails=["perito@chiarisrl.it"])
    settings["capabilities"]["portal_assicurati"] = True
    settings["portal_domains"] = ["chiari.example"]
    locked = apply_profile_locks(settings)
    caps = capabilities_for(locked)

    assert caps["portal_assicurati"] is False
    assert caps["cat_dispatcher"] is False
    assert caps["videoperizia"] is False
    assert caps["inviti_utenti"] is False
    assert caps["whatsapp"] is False
    assert caps["chiamate_perx"] is False
    assert caps["link_pubblici"] is False
    assert caps["studio_condiviso"] is False
    assert caps["posta"] is True
    assert caps["sala_regia"] is True
    assert caps["sinistri"] is True
    assert locked["portal_domains"] == []
    assert locked["cat_settings"]["enabled"] is False
    assert locked["video_inspection_settings"]["enabled"] is False
    assert allows(locked, "portal_assicurati") is False


def test_studio_profile_keeps_the_full_product():
    caps = capabilities_for({})
    assert caps["portal_assicurati"] is True
    assert caps["cat_dispatcher"] is True
    assert caps["sala_regia"] is False


def test_reclaim_model_thresholds():
    light = workflow_reclaim(Decimal("5000"), esito="CONCORDATO")
    over = workflow_reclaim(Decimal("5000.01"), esito="CONCORDATO")
    non_concordata = workflow_reclaim(Decimal("100"), esito="NON_CONCORDATO")
    negativa = workflow_reclaim(Decimal("9000"), esito="NEGATIVO")
    zero = workflow_reclaim(Decimal("0"), esito="CONCORDATO")
    assente = workflow_reclaim(Decimal("100"), esito="CONCORDATO", reclaim_assente=True)

    assert light["reclaim"]["modello"] == "Light"
    assert over["reclaim"]["modello"] == "Over"
    assert non_concordata["reclaim"]["modello"] == "Over"
    assert negativa["reclaim"]["modello"] == "Sopralluogo Senza stima"
    assert zero["reclaim"]["modello"] == "Sopralluogo Senza stima"
    assert assente["reclaim"]["compilare"] is False
    assert assente["salesforce"]["genera_relazione"] is True


def test_economic_hash_ignores_text_and_keeps_amounts():
    base = {
        "selezione_allegati": {"esito": "CONCORDATO"},
        "totali": {"liquidabile": 1200},
        "testi": {"atto": "frase che non conta"},
        "liquidazioni": [{"garanzia_id": "fe", "liquidabile": 1200, "danno_accertato": 1300}],
    }
    changed_text = dict(base)
    changed_text["testi"] = {"atto": "altra frase"}
    changed_amount = {
        **base,
        "totali": {"liquidabile": 800},
        "liquidazioni": [{"garanzia_id": "fe", "liquidabile": 800, "danno_accertato": 1300}],
    }
    assert hash_economico(base) == hash_economico(changed_text)
    assert hash_economico(base) != hash_economico(changed_amount)


def test_amount_floor_and_iban_questions():
    assert liquidabile_consentito(Decimal("100"), Decimal("80"), None) is True
    assert liquidabile_consentito(Decimal("70"), Decimal("80"), None) is False
    assert liquidabile_consentito(Decimal("70"), Decimal("80"), "il perito ha ridotto") is True
    assert iban_mod97_ok("IT60X0542811101000000123456") is True
    assert iban_mod97_ok("IT60X0542811101000000123457") is False
    assert (
        iban_richiede_questione(
            iban_precedente="IT60X0542811101000000123456",
            iban_nuovo="IT60X0542811101000000123456",
            beneficiario_e_intestatario=True,
        )
        is None
    )
    assert (
        iban_richiede_questione(
            iban_precedente=None,
            iban_nuovo="IT60X0542811101000000123456",
            beneficiario_e_intestatario=False,
        )
        == "beneficiario_terzo"
    )


def test_dated_rules_and_claim_mapping_keep_counts_without_names():
    rules = extract_dated_rules("- **Foto (perito 25/11):** chi guarda le foto compila la selezione una per una, senza lasciare il tipo generico.")
    assert rules[0]["origin_label"] == "perito 25/11"
    mapped = map_claim(
        "tenant",
        {
            "rif_chiari": "26-1",
            "stato": "CHIUSO",
            "numero": "123",
            "assicurato": "Mario Rossi",
            "stima_deterministica": {
                "revisione": 1,
                "input": {},
                "calcolo": {"totali": {"liquidabile": 10}, "hash_calcolo": "abc"},
                "approvazione": {"revisione": 1, "data": "2026-11-01T00:00:00+00:00", "hash_calcolo": "abc"},
            },
            "atti_inviati": [{"importo": 10, "ora": "2026-11-02T00:00:00+00:00"}],
            "collegati": {"gruppo": "g1", "motivo": "stesso fabbricato", "sinistri": ["26-1", "26-2"]},
        },
    )
    summary = summarize([mapped])
    assert summary["pratiche"] == 1
    assert summary["per_stato"]["CHIUSO"] == 1
    assert summary["revisioni"] == 1
    assert mapped["revisions"][0]["approved"] is True
    assert "Mario Rossi" not in json_summary(summary)


def json_summary(summary: dict) -> str:
    return str(summary)
