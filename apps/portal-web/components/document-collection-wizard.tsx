"use client";

import { useEffect, useMemo, useState } from "react";

import {
  createUploadIntent,
  getDocumentCollectionDraft,
  saveDocumentCollectionDraft,
  submitDocumentCollection,
  uploadPortalDocumentFile
} from "@/lib/api";
import type { PortalSession } from "@/lib/types";

type UploadedArtifact = {
  document_id: string;
  file_name: string;
  category: string;
  kind: string;
  status: string;
  uploaded_at?: string;
  item_index?: number;
  item_label?: string;
  component_name?: string;
  storage_path?: string;
};

type ItemDraft = {
  itemType: string;
  brand: string;
  model: string;
  purchaseYear: string;
  purchaseYearApproximate: boolean;
  damageType: string;
  damageDynamics: string;
  hasDamagedComponents: boolean;
  damagedComponents: string[];
  wholeItemUploads: UploadedArtifact[];
  componentUploads: Record<string, UploadedArtifact[]>;
  optionalVideosUploads: UploadedArtifact[];
  optionalSupportingDocsUploads: UploadedArtifact[];
};

type ConfirmationKey =
  | "authentic_photos"
  | "photos_match_insured_property"
  | "photos_clear_for_damage_assessment"
  | "preserve_damaged_goods_until_claim_closed"
  | "no_additional_damaged_goods";

type WizardStep =
  | { kind: "inventory" }
  | { kind: "item-details"; itemIndex: number }
  | { kind: "building" }
  | { kind: "item-assets"; itemIndex: number }
  | { kind: "receipts" }
  | { kind: "summary" }
  | { kind: "confirmations" };

type DraftState = {
  step_kind: WizardStep["kind"];
  step_item_index: number;
  inventory_count: number;
  notes: string;
  confirmations: Record<ConfirmationKey, boolean>;
  buildingUploads: UploadedArtifact[];
  repairReceiptUploads: UploadedArtifact[];
  items: ItemDraft[];
};

const CONFIRMATION_COPY: Record<ConfirmationKey, string> = {
  authentic_photos: "Confermo che le foto sono autentiche e non manipolate",
  photos_match_insured_property: "Confermo che le foto si riferiscono al fabbricato assicurato",
  photos_clear_for_damage_assessment:
    "Confermo che le foto sono nitide e permettono di valutare il danno",
  preserve_damaged_goods_until_claim_closed:
    "Mi impegno a conservare i beni danneggiati fino alla chiusura del sinistro",
  no_additional_damaged_goods:
    "Confermo che non sono presenti altri beni danneggiati dal sinistro in oggetto oltre quelli qui riportati"
};

function createItemDraft(): ItemDraft {
  return {
    itemType: "",
    brand: "",
    model: "",
    purchaseYear: "",
    purchaseYearApproximate: false,
    damageType: "",
    damageDynamics: "",
    hasDamagedComponents: false,
    damagedComponents: [],
    wholeItemUploads: [],
    componentUploads: {},
    optionalVideosUploads: [],
    optionalSupportingDocsUploads: []
  };
}

function createDefaultDraft(): DraftState {
  return {
    step_kind: "inventory",
    step_item_index: 0,
    inventory_count: 1,
    notes: "",
    confirmations: {
      authentic_photos: false,
      photos_match_insured_property: false,
      photos_clear_for_damage_assessment: false,
      preserve_damaged_goods_until_claim_closed: false,
      no_additional_damaged_goods: false
    },
    buildingUploads: [],
    repairReceiptUploads: [],
    items: [createItemDraft()]
  };
}

function normalizeArtifact(value: unknown): UploadedArtifact | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const candidate = value as Record<string, unknown>;
  const documentId = typeof candidate.document_id === "string" ? candidate.document_id : "";
  const fileName = typeof candidate.file_name === "string" ? candidate.file_name : "";
  const category = typeof candidate.category === "string" ? candidate.category : "";
  const kind = typeof candidate.kind === "string" ? candidate.kind : "";
  if (!documentId || !fileName || !kind) {
    return null;
  }
  return {
    document_id: documentId,
    file_name: fileName,
    category,
    kind,
    status: typeof candidate.status === "string" ? candidate.status : "uploaded",
    uploaded_at: typeof candidate.uploaded_at === "string" ? candidate.uploaded_at : undefined,
    item_index: typeof candidate.item_index === "number" ? candidate.item_index : undefined,
    item_label: typeof candidate.item_label === "string" ? candidate.item_label : undefined,
    component_name:
      typeof candidate.component_name === "string" ? candidate.component_name : undefined,
    storage_path: typeof candidate.storage_path === "string" ? candidate.storage_path : undefined
  };
}

function normalizeArtifactList(value: unknown): UploadedArtifact[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const seen = new Set<string>();
  return value
    .map((entry) => normalizeArtifact(entry))
    .filter((entry): entry is UploadedArtifact => Boolean(entry))
    .filter((entry) => {
      if (seen.has(entry.document_id)) {
        return false;
      }
      seen.add(entry.document_id);
      return true;
    });
}

function normalizeItemDraft(value: unknown): ItemDraft {
  const base = createItemDraft();
  if (!value || typeof value !== "object") {
    return base;
  }
  const candidate = value as Record<string, unknown>;
  const componentUploadsRaw =
    typeof candidate.componentUploads === "object" && candidate.componentUploads
      ? (candidate.componentUploads as Record<string, unknown>)
      : {};
  const componentUploads: Record<string, UploadedArtifact[]> = {};
  for (const [key, entry] of Object.entries(componentUploadsRaw)) {
    componentUploads[key] = normalizeArtifactList(entry);
  }
  return {
    itemType: typeof candidate.itemType === "string" ? candidate.itemType : "",
    brand: typeof candidate.brand === "string" ? candidate.brand : "",
    model: typeof candidate.model === "string" ? candidate.model : "",
    purchaseYear: typeof candidate.purchaseYear === "string" ? candidate.purchaseYear : "",
    purchaseYearApproximate: candidate.purchaseYearApproximate === true,
    damageType: typeof candidate.damageType === "string" ? candidate.damageType : "",
    damageDynamics: typeof candidate.damageDynamics === "string" ? candidate.damageDynamics : "",
    hasDamagedComponents: candidate.hasDamagedComponents === true,
    damagedComponents: Array.isArray(candidate.damagedComponents)
      ? candidate.damagedComponents.map((item) => String(item).trim()).filter(Boolean)
      : [],
    wholeItemUploads: normalizeArtifactList(candidate.wholeItemUploads),
    componentUploads,
    optionalVideosUploads: normalizeArtifactList(candidate.optionalVideosUploads),
    optionalSupportingDocsUploads: normalizeArtifactList(candidate.optionalSupportingDocsUploads)
  };
}

function normalizeDraftState(value: unknown): DraftState {
  const defaults = createDefaultDraft();
  if (!value || typeof value !== "object") {
    return defaults;
  }
  const candidate = value as Record<string, unknown>;
  const items = Array.isArray(candidate.items)
    ? candidate.items.map((item) => normalizeItemDraft(item))
    : defaults.items;
  const inventoryCount = Math.max(
    1,
    typeof candidate.inventory_count === "number" ? candidate.inventory_count : items.length
  );
  const confirmationsRaw =
    typeof candidate.confirmations === "object" && candidate.confirmations
      ? (candidate.confirmations as Record<string, unknown>)
      : {};

  return {
    step_kind:
      candidate.step_kind === "item-details" ||
      candidate.step_kind === "building" ||
      candidate.step_kind === "item-assets" ||
      candidate.step_kind === "receipts" ||
      candidate.step_kind === "summary" ||
      candidate.step_kind === "confirmations"
        ? candidate.step_kind
        : "inventory",
    step_item_index:
      typeof candidate.step_item_index === "number" ? Math.max(0, candidate.step_item_index) : 0,
    inventory_count: inventoryCount,
    notes: typeof candidate.notes === "string" ? candidate.notes : "",
    confirmations: {
      authentic_photos: confirmationsRaw.authentic_photos === true,
      photos_match_insured_property: confirmationsRaw.photos_match_insured_property === true,
      photos_clear_for_damage_assessment:
        confirmationsRaw.photos_clear_for_damage_assessment === true,
      preserve_damaged_goods_until_claim_closed:
        confirmationsRaw.preserve_damaged_goods_until_claim_closed === true,
      no_additional_damaged_goods: confirmationsRaw.no_additional_damaged_goods === true
    },
    buildingUploads: normalizeArtifactList(candidate.buildingUploads),
    repairReceiptUploads: normalizeArtifactList(candidate.repairReceiptUploads),
    items:
      items.length >= inventoryCount
        ? items
        : [...items, ...Array.from({ length: inventoryCount - items.length }, () => createItemDraft())]
  };
}

function serializeDraft(state: DraftState): Record<string, unknown> {
  return {
    step_kind: state.step_kind,
    step_item_index: state.step_item_index,
    inventory_count: state.inventory_count,
    notes: state.notes,
    confirmations: state.confirmations,
    buildingUploads: state.buildingUploads,
    repairReceiptUploads: state.repairReceiptUploads,
    items: state.items
  };
}

function totalStepsForItems(itemsCount: number) {
  return 1 + itemsCount + 1 + itemsCount + 1 + 1 + 1;
}

function stepNumber(step: WizardStep, itemsCount: number) {
  if (step.kind === "inventory") {
    return 1;
  }
  if (step.kind === "item-details") {
    return 2 + step.itemIndex;
  }
  if (step.kind === "building") {
    return 2 + itemsCount;
  }
  if (step.kind === "item-assets") {
    return 3 + itemsCount + step.itemIndex;
  }
  if (step.kind === "receipts") {
    return 3 + itemsCount + itemsCount;
  }
  if (step.kind === "summary") {
    return 4 + itemsCount + itemsCount;
  }
  return 5 + itemsCount + itemsCount;
}

function humanItemLabel(item: ItemDraft, index: number) {
  return item.itemType.trim() || `Bene ${index + 1}`;
}

function buildStep(state: DraftState, selectedIndex: number): WizardStep {
  const itemIndex = Math.min(state.step_item_index ?? selectedIndex, state.items.length - 1);
  switch (state.step_kind) {
    case "item-details":
      return { kind: "item-details", itemIndex };
    case "item-assets":
      return { kind: "item-assets", itemIndex };
    case "building":
      return { kind: "building" };
    case "receipts":
      return { kind: "receipts" };
    case "summary":
      return { kind: "summary" };
    case "confirmations":
      return { kind: "confirmations" };
    default:
      return { kind: "inventory" };
  }
}

function toUploadedArtifact(params: {
  documentId: string;
  fileName: string;
  category: string;
  kind: string;
  status: string;
  uploadedAt?: string;
  itemIndex?: number;
  itemLabel?: string;
  componentName?: string;
  storagePath?: string;
}): UploadedArtifact {
  return {
    document_id: params.documentId,
    file_name: params.fileName,
    category: params.category,
    kind: params.kind,
    status: params.status,
    uploaded_at: params.uploadedAt,
    item_index: params.itemIndex,
    item_label: params.itemLabel,
    component_name: params.componentName,
    storage_path: params.storagePath
  };
}

export function DocumentCollectionWizard({
  session,
  claimId,
  onSubmitted
}: {
  session: PortalSession;
  claimId: string;
  onSubmitted: (message: string) => Promise<void> | void;
}) {
  const [draft, setDraft] = useState<DraftState>(createDefaultDraft());
  const [currentIndex, setCurrentIndex] = useState(0);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isLoadingDraft, setIsLoadingDraft] = useState(true);
  const [isSavingDraft, setIsSavingDraft] = useState(false);
  const [uploadingLabel, setUploadingLabel] = useState<string | null>(null);

  const step = buildStep(draft, currentIndex);
  const currentItem =
    step.kind === "item-details" || step.kind === "item-assets"
      ? draft.items[step.itemIndex]
      : null;
  const totalSteps = totalStepsForItems(draft.items.length);
  const currentStepNumber = stepNumber(step, draft.items.length);
  const allConfirmationsChecked = Object.values(draft.confirmations).every(Boolean);

  useEffect(() => {
    let active = true;
    void (async () => {
      try {
        const response = await getDocumentCollectionDraft(session, claimId);
        if (!active) {
          return;
        }
        const normalized = normalizeDraftState(response.draft_json);
        setDraft(normalized);
      } catch (requestError) {
        if (!active) {
          return;
        }
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Impossibile recuperare il progresso della documentale."
        );
      } finally {
        if (active) {
          setIsLoadingDraft(false);
        }
      }
    })();
    return () => {
      active = false;
    };
  }, [claimId, session]);

  useEffect(() => {
    if (isLoadingDraft || isSubmitting) {
      return;
    }
    const timeoutId = window.setTimeout(() => {
      setIsSavingDraft(true);
      void (async () => {
        try {
          await saveDocumentCollectionDraft(
            session,
            {
              draftJson: serializeDraft(draft)
            },
            claimId
          );
        } catch (requestError) {
          setError(
            requestError instanceof Error
              ? requestError.message
              : "Impossibile salvare l'avanzamento."
          );
        } finally {
          setIsSavingDraft(false);
        }
      })();
    }, 450);
    return () => window.clearTimeout(timeoutId);
  }, [claimId, draft, isLoadingDraft, isSubmitting, session]);

  function updateDraft(updater: (current: DraftState) => DraftState) {
    setDraft((current) => {
      const next = updater(current);
      if (next.items.length !== current.items.length) {
        setCurrentIndex((previous) => Math.min(previous, next.items.length - 1));
      }
      return next;
    });
  }

  function updateItemsCount(nextCount: number) {
    const normalized = Math.min(10, Math.max(1, nextCount));
    updateDraft((current) => {
      const nextItems = Array.from({ length: normalized }, (_, index) => current.items[index] ?? createItemDraft());
      return {
        ...current,
        inventory_count: normalized,
        items: nextItems
      };
    });
  }

  function updateItem(itemIndex: number, updater: (item: ItemDraft) => ItemDraft) {
    updateDraft((current) => ({
      ...current,
      items: current.items.map((item, index) => (index === itemIndex ? updater(item) : item))
    }));
  }

  function setComponentNames(itemIndex: number, rawValue: string) {
    const names = rawValue
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
    updateItem(itemIndex, (item) => {
      const nextComponentUploads: Record<string, UploadedArtifact[]> = {};
      for (const name of names) {
        nextComponentUploads[name] = item.componentUploads[name] ?? [];
      }
      return {
        ...item,
        damagedComponents: names,
        componentUploads: nextComponentUploads
      };
    });
  }

  function currentStepValid() {
    if (step.kind === "inventory") {
      return draft.inventory_count >= 1;
    }
    if (step.kind === "item-details" && currentItem) {
      return (
        currentItem.itemType.trim().length > 0 &&
        currentItem.purchaseYear.trim().length > 0 &&
        currentItem.damageType.trim().length > 0 &&
        currentItem.damageDynamics.trim().length > 0 &&
        (!currentItem.hasDamagedComponents || currentItem.damagedComponents.length > 0)
      );
    }
    if (step.kind === "building") {
      return draft.buildingUploads.length >= 2;
    }
    if (step.kind === "item-assets" && currentItem) {
      return (
        currentItem.wholeItemUploads.length >= 1 &&
        currentItem.damagedComponents.every(
          (component) => (currentItem.componentUploads[component] ?? []).length >= 1
        )
      );
    }
    if (step.kind === "receipts") {
      return draft.repairReceiptUploads.length >= 1;
    }
    if (step.kind === "confirmations") {
      return allConfirmationsChecked;
    }
    return true;
  }

  function setStep(nextStep: WizardStep) {
    setDraft((current) => ({
      ...current,
      step_kind: nextStep.kind,
      step_item_index:
        nextStep.kind === "item-details" || nextStep.kind === "item-assets"
          ? nextStep.itemIndex
          : current.step_item_index
    }));
    if (nextStep.kind === "item-details" || nextStep.kind === "item-assets") {
      setCurrentIndex(nextStep.itemIndex);
    }
  }

  function goNext() {
    if (!currentStepValid()) {
      setError("Completa i campi obbligatori prima di proseguire.");
      return;
    }
    setError(null);

    if (step.kind === "inventory") {
      setStep({ kind: "item-details", itemIndex: 0 });
      return;
    }
    if (step.kind === "item-details") {
      if (step.itemIndex < draft.items.length - 1) {
        setStep({ kind: "item-details", itemIndex: step.itemIndex + 1 });
        return;
      }
      setStep({ kind: "building" });
      return;
    }
    if (step.kind === "building") {
      setStep({ kind: "item-assets", itemIndex: 0 });
      return;
    }
    if (step.kind === "item-assets") {
      if (step.itemIndex < draft.items.length - 1) {
        setStep({ kind: "item-assets", itemIndex: step.itemIndex + 1 });
        return;
      }
      setStep({ kind: "receipts" });
      return;
    }
    if (step.kind === "receipts") {
      setStep({ kind: "summary" });
      return;
    }
    if (step.kind === "summary") {
      setStep({ kind: "confirmations" });
    }
  }

  function goPrevious() {
    setError(null);
    if (step.kind === "confirmations") {
      setStep({ kind: "summary" });
      return;
    }
    if (step.kind === "summary") {
      setStep({ kind: "receipts" });
      return;
    }
    if (step.kind === "receipts") {
      setStep({ kind: "item-assets", itemIndex: draft.items.length - 1 });
      return;
    }
    if (step.kind === "item-assets") {
      if (step.itemIndex > 0) {
        setStep({ kind: "item-assets", itemIndex: step.itemIndex - 1 });
        return;
      }
      setStep({ kind: "building" });
      return;
    }
    if (step.kind === "building") {
      setStep({ kind: "item-details", itemIndex: draft.items.length - 1 });
      return;
    }
    if (step.kind === "item-details") {
      if (step.itemIndex > 0) {
        setStep({ kind: "item-details", itemIndex: step.itemIndex - 1 });
        return;
      }
      setStep({ kind: "inventory" });
    }
  }

  async function uploadFiles(
    files: File[],
    options: {
      label: string;
      category: string;
      kind: string;
      itemIndex?: number;
      itemLabel?: string;
      componentName?: string;
    },
    onUploaded: (artifacts: UploadedArtifact[]) => void
  ) {
    if (files.length === 0) {
      return;
    }
    setUploadingLabel(options.label);
    setError(null);
    try {
      const uploadedArtifacts: UploadedArtifact[] = [];
      for (const file of files) {
        const intent = await createUploadIntent(
          session,
          {
            fileName: file.name,
            mimeType: file.type,
            sizeBytes: file.size,
            category: options.category
          },
          claimId
        );
        const uploaded = await uploadPortalDocumentFile(
          session,
          {
            documentId: intent.document_id,
            file
          },
          claimId
        );
        uploadedArtifacts.push(
          toUploadedArtifact({
            documentId: uploaded.document_id,
            fileName: uploaded.file_name,
            category: options.category,
            kind: options.kind,
            status: uploaded.status,
            uploadedAt: uploaded.uploaded_at,
            itemIndex: options.itemIndex,
            itemLabel: options.itemLabel,
            componentName: options.componentName,
            storagePath: uploaded.storage_path
          })
        );
      }
      onUploaded(uploadedArtifacts);
    } catch (requestError) {
      setError(
        requestError instanceof Error ? requestError.message : "Caricamento file non riuscito."
      );
    } finally {
      setUploadingLabel(null);
    }
  }

  async function handleSubmit() {
    if (step.kind !== "confirmations" || !allConfirmationsChecked) {
      setError("Conferma tutte le dichiarazioni richieste prima dell'invio.");
      return;
    }

    setIsSubmitting(true);
    setError(null);

    try {
      const uploadRegistrations = [
        ...draft.buildingUploads,
        ...draft.repairReceiptUploads,
        ...draft.items.flatMap((item, index) => [
          ...item.wholeItemUploads.map((entry) => ({ ...entry, item_index: index + 1 })),
          ...item.optionalVideosUploads.map((entry) => ({ ...entry, item_index: index + 1 })),
          ...item.optionalSupportingDocsUploads.map((entry) => ({ ...entry, item_index: index + 1 })),
          ...item.damagedComponents.flatMap((component) =>
            (item.componentUploads[component] ?? []).map((entry) => ({
              ...entry,
              item_index: index + 1,
              component_name: component
            }))
          )
        ])
      ];

      const response = await submitDocumentCollection(
        session,
        {
          notes: draft.notes,
          photosCount: uploadRegistrations.filter((entry) => entry.category !== "documentale_video").length,
          items: draft.items.map((item) => ({
            name: item.itemType,
            brand: item.brand || undefined,
            model: item.model || undefined,
            purchaseYear: Number(item.purchaseYear),
            quantity: 1
          })),
          metadataJson: {
            wizard_version: 3,
            workflow: "guided_document_collection",
            upload_intents: uploadRegistrations,
            confirmations: draft.confirmations,
            draft_snapshot: serializeDraft(draft),
            items: draft.items.map((item, index) => ({
              index: index + 1,
              item_type: item.itemType,
              brand: item.brand || null,
              model: item.model || null,
              purchase_year: Number(item.purchaseYear),
              purchase_year_approximate: item.purchaseYearApproximate,
              damage_type: item.damageType,
              damage_dynamics: item.damageDynamics,
              damaged_components: item.damagedComponents,
              whole_item_files: item.wholeItemUploads.map((entry) => entry.file_name),
              component_files: Object.fromEntries(
                item.damagedComponents.map((component) => [
                  component,
                  (item.componentUploads[component] ?? []).map((entry) => entry.file_name)
                ])
              ),
              optional_videos: item.optionalVideosUploads.map((entry) => entry.file_name),
              optional_supporting_documents: item.optionalSupportingDocsUploads.map(
                (entry) => entry.file_name
              )
            }))
          }
        },
        claimId
      );

      const message = `Documentazione ricevuta: ${uploadRegistrations.length} file acquisiti alle ${new Date(
        response.submitted_at
      ).toLocaleString("it-IT")}`;
      setResult(message);
      await onSubmitted(message);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Invio documentale non riuscito."
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  if (isLoadingDraft) {
    return <p className="feedback">Ripristino del progresso in corso...</p>;
  }

  return (
    <div className="wizard-shell">
      <div className="wizard-header">
        <div>
          <p className="section-card__eyebrow">Procedura guidata</p>
          <h3>Documentale sinistro</h3>
          <p className="support-copy">
            Il progresso viene salvato automaticamente. Se esci o cambi dispositivo ritrovi il
            lavoro dove lo hai lasciato.
          </p>
        </div>
        <div className="wizard-progress">
          <span>
            Step {currentStepNumber} di {totalSteps}
            {isSavingDraft ? " · salvataggio..." : ""}
          </span>
          <div className="wizard-progress__bar">
            <div
              className="wizard-progress__bar-fill"
              style={{ width: `${(currentStepNumber / totalSteps) * 100}%` }}
            />
          </div>
        </div>
      </div>

      {step.kind === "inventory" ? (
        <div className="wizard-step-card">
          <h4>Quanti beni risultano danneggiati?</h4>
          <p className="support-copy">
            Inserisci il numero totale dei beni coinvolti. Poi ti guideremo bene per bene.
          </p>
          <label className="mini-form">
            <span>Numero beni</span>
            <input
              type="number"
              min={1}
              max={10}
              value={draft.inventory_count}
              onChange={(event) => updateItemsCount(Number(event.target.value || "1"))}
            />
          </label>
        </div>
      ) : null}

      {step.kind === "item-details" && currentItem ? (
        <div className="wizard-step-card">
          <h4>Dettagli bene {step.itemIndex + 1}</h4>
          <p className="support-copy">
            Raccogliamo prima i dati del bene e del danno. Le fotografie arrivano dopo.
          </p>
          <div className="mini-form">
            <label>
              Che bene e?
              <input
                value={currentItem.itemType}
                onChange={(event) =>
                  updateItem(step.itemIndex, (item) => ({ ...item, itemType: event.target.value }))
                }
                placeholder="Caldaia, forno, lavatrice..."
              />
            </label>
            <div className="field-grid field-grid--double">
              <label>
                Marca
                <input
                  value={currentItem.brand}
                  onChange={(event) =>
                    updateItem(step.itemIndex, (item) => ({ ...item, brand: event.target.value }))
                  }
                  placeholder="Opzionale"
                />
              </label>
              <label>
                Modello
                <input
                  value={currentItem.model}
                  onChange={(event) =>
                    updateItem(step.itemIndex, (item) => ({ ...item, model: event.target.value }))
                  }
                  placeholder="Opzionale"
                />
              </label>
            </div>
            <div className="field-grid field-grid--double">
              <label>
                Anno di acquisto
                <input
                  value={currentItem.purchaseYear}
                  onChange={(event) =>
                    updateItem(step.itemIndex, (item) => ({
                      ...item,
                      purchaseYear: event.target.value.replace(/\D/g, "").slice(0, 4)
                    }))
                  }
                  placeholder="2021"
                />
              </label>
              <label className="wizard-checkbox">
                <input
                  type="checkbox"
                  checked={currentItem.purchaseYearApproximate}
                  onChange={(event) =>
                    updateItem(step.itemIndex, (item) => ({
                      ...item,
                      purchaseYearApproximate: event.target.checked
                    }))
                  }
                />
                <span>Anno approssimato</span>
              </label>
            </div>
            <label>
              Che tipo di danno e stato riscontrato?
              <input
                value={currentItem.damageType}
                onChange={(event) =>
                  updateItem(step.itemIndex, (item) => ({ ...item, damageType: event.target.value }))
                }
                placeholder="Non si accende, bruciatura, scheda guasta..."
              />
            </label>
            <label>
              Descrivi la dinamica
              <textarea
                value={currentItem.damageDynamics}
                onChange={(event) =>
                  updateItem(step.itemIndex, (item) => ({
                    ...item,
                    damageDynamics: event.target.value
                  }))
                }
                placeholder="Spiega brevemente come si e manifestato il danno."
              />
            </label>
            <label className="wizard-checkbox">
              <input
                type="checkbox"
                checked={currentItem.hasDamagedComponents}
                onChange={(event) =>
                  updateItem(step.itemIndex, (item) => ({
                    ...item,
                    hasDamagedComponents: event.target.checked,
                    damagedComponents: event.target.checked ? item.damagedComponents : [],
                    componentUploads: event.target.checked ? item.componentUploads : {}
                  }))
                }
              />
              <span>Sono presenti componenti danneggiati</span>
            </label>
            {currentItem.hasDamagedComponents ? (
              <label>
                Quali componenti risultano danneggiati?
                <textarea
                  value={currentItem.damagedComponents.join(", ")}
                  onChange={(event) => setComponentNames(step.itemIndex, event.target.value)}
                  placeholder="Scheda, alimentatore, display..."
                />
              </label>
            ) : null}
          </div>
        </div>
      ) : null}

      {step.kind === "building" ? (
        <div className="wizard-step-card">
          <h4>Foto del fabbricato</h4>
          <p className="support-copy">
            Carica almeno 2 foto del fabbricato assicurato. Una volta acquisite, non potranno
            essere rimosse dal portale.
          </p>
          <label className="mini-form">
            <span>Foto del fabbricato</span>
            <input
              type="file"
              accept="image/*"
              multiple
              onChange={(event) => {
                const files = Array.from(event.target.files ?? []);
                void uploadFiles(
                  files,
                  {
                    label: "foto del fabbricato",
                    category: "documentale_fabbricato",
                    kind: "building_photo"
                  },
                  (artifacts) =>
                    updateDraft((current) => ({
                      ...current,
                      buildingUploads: [...current.buildingUploads, ...artifacts]
                    }))
                );
                event.currentTarget.value = "";
              }}
            />
          </label>
          <ul className="plain-list">
            {draft.buildingUploads.map((entry) => (
              <li key={entry.document_id}>
                <strong>{entry.file_name}</strong>
                <span>Acquisito dal portale</span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {step.kind === "item-assets" && currentItem ? (
        <div className="wizard-step-card">
          <h4>Documentazione per {humanItemLabel(currentItem, step.itemIndex)}</h4>
          <p className="support-copy">
            Procediamo per bene completo, componenti danneggiati, eventuali video e altri allegati
            utili. I file caricati restano acquisiti e non possono essere rimossi.
          </p>
          <div className="mini-form">
            <label>
              Foto del bene completo
              <input
                type="file"
                accept="image/*"
                multiple
                onChange={(event) => {
                  const files = Array.from(event.target.files ?? []);
                  const itemLabel = humanItemLabel(currentItem, step.itemIndex);
                  void uploadFiles(
                    files,
                    {
                      label: `foto bene ${itemLabel}`,
                      category: "documentale_bene",
                      kind: "whole_item_photo",
                      itemIndex: step.itemIndex + 1,
                      itemLabel
                    },
                    (artifacts) =>
                      updateItem(step.itemIndex, (item) => ({
                        ...item,
                        wholeItemUploads: [...item.wholeItemUploads, ...artifacts]
                      }))
                  );
                  event.currentTarget.value = "";
                }}
              />
            </label>
            <ul className="plain-list">
              {currentItem.wholeItemUploads.map((entry) => (
                <li key={entry.document_id}>
                  <strong>{entry.file_name}</strong>
                  <span>Foto bene acquisita</span>
                </li>
              ))}
            </ul>

            {currentItem.damagedComponents.map((component) => (
              <div key={component} className="mini-form">
                <label>
                  {humanItemLabel(currentItem, step.itemIndex)} · componente: {component}
                  <input
                    type="file"
                    accept="image/*"
                    multiple
                    onChange={(event) => {
                      const files = Array.from(event.target.files ?? []);
                      const itemLabel = humanItemLabel(currentItem, step.itemIndex);
                      void uploadFiles(
                        files,
                        {
                          label: `foto componente ${component}`,
                          category: "documentale_componente",
                          kind: "component_photo",
                          itemIndex: step.itemIndex + 1,
                          itemLabel,
                          componentName: component
                        },
                        (artifacts) =>
                          updateItem(step.itemIndex, (item) => ({
                            ...item,
                            componentUploads: {
                              ...item.componentUploads,
                              [component]: [...(item.componentUploads[component] ?? []), ...artifacts]
                            }
                          }))
                      );
                      event.currentTarget.value = "";
                    }}
                  />
                </label>
                <ul className="plain-list">
                  {(currentItem.componentUploads[component] ?? []).map((entry) => (
                    <li key={entry.document_id}>
                      <strong>{entry.file_name}</strong>
                      <span>Foto componente acquisita</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}

            <label>
              Video opzionali
              <input
                type="file"
                accept="video/*"
                multiple
                onChange={(event) => {
                  const files = Array.from(event.target.files ?? []);
                  const itemLabel = humanItemLabel(currentItem, step.itemIndex);
                  void uploadFiles(
                    files,
                    {
                      label: `video ${itemLabel}`,
                      category: "documentale_video",
                      kind: "video",
                      itemIndex: step.itemIndex + 1,
                      itemLabel
                    },
                    (artifacts) =>
                      updateItem(step.itemIndex, (item) => ({
                        ...item,
                        optionalVideosUploads: [...item.optionalVideosUploads, ...artifacts]
                      }))
                  );
                  event.currentTarget.value = "";
                }}
              />
            </label>
            <ul className="plain-list">
              {currentItem.optionalVideosUploads.map((entry) => (
                <li key={entry.document_id}>
                  <strong>{entry.file_name}</strong>
                  <span>Video acquisito</span>
                </li>
              ))}
            </ul>

            <label>
              Altra documentazione utile
              <input
                type="file"
                accept=".pdf,image/*"
                multiple
                onChange={(event) => {
                  const files = Array.from(event.target.files ?? []);
                  const itemLabel = humanItemLabel(currentItem, step.itemIndex);
                  void uploadFiles(
                    files,
                    {
                      label: `documenti utili ${itemLabel}`,
                      category: "documentale_allegati_utili",
                      kind: "supporting_document",
                      itemIndex: step.itemIndex + 1,
                      itemLabel
                    },
                    (artifacts) =>
                      updateItem(step.itemIndex, (item) => ({
                        ...item,
                        optionalSupportingDocsUploads: [
                          ...item.optionalSupportingDocsUploads,
                          ...artifacts
                        ]
                      }))
                  );
                  event.currentTarget.value = "";
                }}
              />
            </label>
            <ul className="plain-list">
              {currentItem.optionalSupportingDocsUploads.map((entry) => (
                <li key={entry.document_id}>
                  <strong>{entry.file_name}</strong>
                  <span>Documento utile acquisito</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      ) : null}

      {step.kind === "receipts" ? (
        <div className="wizard-step-card">
          <h4>Giustificativi finali</h4>
          <p className="support-copy">
            Carica qui preventivi o fatture per la riparazione o la sostituzione dei beni
            danneggiati. Anche questi file, una volta caricati, restano acquisiti.
          </p>
          <label className="mini-form">
            <span>Fatture / preventivi</span>
            <input
              type="file"
              accept=".pdf,image/*"
              multiple
              onChange={(event) => {
                const files = Array.from(event.target.files ?? []);
                void uploadFiles(
                  files,
                  {
                    label: "giustificativi",
                    category: "documentale_giustificativi",
                    kind: "repair_receipt"
                  },
                  (artifacts) =>
                    updateDraft((current) => ({
                      ...current,
                      repairReceiptUploads: [...current.repairReceiptUploads, ...artifacts]
                    }))
                );
                event.currentTarget.value = "";
              }}
            />
          </label>
          <ul className="plain-list">
            {draft.repairReceiptUploads.map((entry) => (
              <li key={entry.document_id}>
                <strong>{entry.file_name}</strong>
                <span>Giustificativo acquisito</span>
              </li>
            ))}
          </ul>
          <label className="mini-form">
            <span>Note finali</span>
            <textarea
              value={draft.notes}
              onChange={(event) =>
                updateDraft((current) => ({ ...current, notes: event.target.value }))
              }
              placeholder="Aggiungi eventuali informazioni utili per la revisione."
            />
          </label>
        </div>
      ) : null}

      {step.kind === "summary" ? (
        <div className="wizard-step-card">
          <h4>Riepilogo prima dell&apos;invio</h4>
          <p className="support-copy">
            Controlla rapidamente i passaggi completati. Se qualcosa non torna puoi tornare
            indietro e aggiungere altri file.
          </p>
          <ul className="plain-list">
            <li>
              <strong>Beni censiti</strong>
              <span>{draft.items.length}</span>
            </li>
            <li>
              <strong>Foto fabbricato</strong>
              <span>{draft.buildingUploads.length}</span>
            </li>
            <li>
              <strong>Giustificativi</strong>
              <span>{draft.repairReceiptUploads.length}</span>
            </li>
          </ul>
          {draft.items.map((item, index) => (
            <article key={`${humanItemLabel(item, index)}-${index}`} className="wizard-summary-card">
              <strong>{humanItemLabel(item, index)}</strong>
              <span>
                {item.brand || "Marca n/d"}
                {item.model ? ` · ${item.model}` : ""}
              </span>
              <span>
                Danno: {item.damageType} · Componenti:{" "}
                {item.damagedComponents.length > 0 ? item.damagedComponents.join(", ") : "nessuno"}
              </span>
            </article>
          ))}
          {result ? <p className="feedback feedback--success">{result}</p> : null}
        </div>
      ) : null}

      {step.kind === "confirmations" ? (
        <div className="wizard-step-card wizard-step-card--confirmations">
          <div className="wizard-confirmation-header">
            <p className="wizard-confirmation-icon" aria-hidden="true">
              !
            </p>
            <div>
              <h4>Conferma prima di inviare</h4>
              <p className="support-copy">
                Dopo l&apos;invio la documentazione verrà marcata come ricevuta e la pratica
                passerà alla perizia documentale.
              </p>
            </div>
          </div>
          <div className="wizard-confirmation-list">
            {(Object.entries(CONFIRMATION_COPY) as Array<[ConfirmationKey, string]>).map(
              ([key, label]) => (
                <label key={key} className="wizard-confirmation-item">
                  <input
                    type="checkbox"
                    checked={draft.confirmations[key]}
                    onChange={(event) =>
                      updateDraft((current) => ({
                        ...current,
                        confirmations: {
                          ...current.confirmations,
                          [key]: event.target.checked
                        }
                      }))
                    }
                  />
                  <span>{label}</span>
                </label>
              )
            )}
          </div>
        </div>
      ) : null}

      {uploadingLabel ? <p className="feedback">Caricamento in corso: {uploadingLabel}...</p> : null}
      {error ? <p className="feedback feedback--error">{error}</p> : null}

      <div className="wizard-actions">
        {step.kind !== "inventory" ? (
          <button type="button" className="ghost-button" onClick={goPrevious} disabled={isSubmitting}>
            Indietro
          </button>
        ) : (
          <span />
        )}

        {step.kind === "confirmations" ? (
          <button
            type="button"
            onClick={() => void handleSubmit()}
            disabled={isSubmitting || !allConfirmationsChecked}
          >
            {isSubmitting ? "Invio in corso..." : "Conferma e invia documentazione"}
          </button>
        ) : (
          <button type="button" onClick={goNext} disabled={isSubmitting || Boolean(uploadingLabel)}>
            {step.kind === "summary" ? "Vai alle conferme finali" : "Continua"}
          </button>
        )}
      </div>
    </div>
  );
}
