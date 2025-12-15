// Usamos la API v2 de Cloud Functions para Firestore
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

// Inicializar Firebase Admin
initializeApp();
const db = getFirestore();

// 🔥 Se ejecuta cuando se crea una foto o video en la galería
exports.onGalleryItemCreated = onDocumentCreated(
  "users/{uid}/gallery/{mediaId}",
  async (event) => {
    const snap = event.data;
    if (!snap) {
      console.log("No hay snapshot en el evento, se ignora.");
      return;
    }

    const data = snap.data();
    const params = event.params || {};
    const uid = params.uid;
    const mediaId = params.mediaId;

    console.log("Nuevo media en galería:", uid, mediaId, data);

    try {
      await snap.ref.update({
        status: "approved", // 👈 por ahora aprobamos todo
        moderatedAt: FieldValue.serverTimestamp(),
      });

      console.log("Media aprobado automáticamente:", uid, mediaId);
    } catch (err) {
      console.error("Error al actualizar el media:", err);
    }
  }
);
