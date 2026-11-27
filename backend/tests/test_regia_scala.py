from app.domain.regia_scala import controllo_l0, esito_fase, istruzioni, livello, risorsa_libera


def test_mail_starts_at_l1_and_climbs_after_a_failed_check():
    assert livello("classifica_mail", 0, sale=False) == "L1"
    assert livello("classifica_mail", 1, sale=True) == "L3"
    assert livello("classifica_mail", 3, sale=True) is None


def test_approval_is_always_the_perito():
    assert livello("approvazione", 0, sale=False) is None


def test_local_model_waits_until_the_mac_is_idle_and_chrome_is_single():
    assert risorsa_libera("modello_locale", 0, mac_libero=False) is False
    assert risorsa_libera("modello_locale", 0, mac_libero=True) is True
    assert risorsa_libera("modello_locale", 1, mac_libero=True) is False
    assert risorsa_libera("chrome", 0, mac_libero=False) is True
    assert risorsa_libera("chrome", 1, mac_libero=True) is False
    assert risorsa_libera("perito", 0, mac_libero=True) is False


def test_l0_accepts_only_a_known_mail_class_and_a_valid_iban():
    assert controllo_l0("classifica_mail", {"classe": "atto_firmato"}) is True
    assert controllo_l0("classifica_mail", {"classe": "bozza"}) is False
    assert controllo_l0("estrai_iban", {"iban": "IT60X0542811101000000123456"}) is True
    assert controllo_l0("importi", {}) is False


def test_phase_outcomes_match_the_queue_and_rules_enter_the_prompt():
    assert esito_fase("nuovo_incarico") == "DAL_PERITO"
    assert esito_fase("atto_inviato") == "STIMA_DA_RIVEDERE"
    assert esito_fase("chiusura") == "CHIUSURA_DA_RIVEDERE"
    text = istruzioni(["  guarda le foto una per una  ", ""])
    assert "guarda le foto una per una" in text
    assert istruzioni([]) == ""
