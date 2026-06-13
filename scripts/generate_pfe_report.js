const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  HeadingLevel, AlignmentType, WidthType, BorderStyle, ShadingType,
  TableLayoutType, convertInchesToTwip, LevelFormat, UnderlineType
} = require('docx');
const fs = require('fs');
const path = require('path');

// ─── Helpers ────────────────────────────────────────────────────────────────

const COLOR = {
  teal:      '1A6B6B',
  tealLight: 'E8F5F5',
  darkBg:    '1E1E2E',
  gray:      '595959',
  lightGray: 'F2F2F2',
  white:     'FFFFFF',
  accent:    '2E7D7D',
  black:     '000000',
};

function h1(text) {
  return new Paragraph({
    text,
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 400, after: 160 },
    run: { bold: true, color: COLOR.teal, size: 36 },
  });
}

function h2(text) {
  return new Paragraph({
    text,
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 320, after: 120 },
    thematicBreak: false,
    run: { bold: true, color: COLOR.accent, size: 28 },
  });
}

function h3(text) {
  return new Paragraph({
    text,
    heading: HeadingLevel.HEADING_3,
    spacing: { before: 240, after: 80 },
    run: { bold: true, color: COLOR.gray, size: 24 },
  });
}

function para(text, opts = {}) {
  return new Paragraph({
    children: [new TextRun({ text, size: 22, color: COLOR.black, ...opts })],
    spacing: { after: 120 },
  });
}

function bold(text) {
  return new TextRun({ text, bold: true, size: 22 });
}

function mixedPara(runs, spacingAfter = 120) {
  return new Paragraph({
    children: runs,
    spacing: { after: spacingAfter },
  });
}

function bullet(text, level = 0) {
  return new Paragraph({
    children: [new TextRun({ text, size: 22 })],
    bullet: { level },
    spacing: { after: 80 },
  });
}

function codePara(text) {
  return new Paragraph({
    children: [new TextRun({
      text,
      font: 'Courier New',
      size: 18,
      color: '1A6B6B',
    })],
    shading: { type: ShadingType.SOLID, color: 'F0F7F7' },
    spacing: { after: 40 },
    indent: { left: convertInchesToTwip(0.3) },
  });
}

function separator() {
  return new Paragraph({
    text: '',
    border: { bottom: { color: COLOR.teal, size: 6, space: 1, style: BorderStyle.SINGLE } },
    spacing: { after: 200 },
  });
}

function pageBreak() {
  return new Paragraph({ pageBreakBefore: true, text: '' });
}

// ─── Table builder ───────────────────────────────────────────────────────────

function makeTable(headers, rows, colWidths) {
  const headerRow = new TableRow({
    tableHeader: true,
    children: headers.map((h, i) =>
      new TableCell({
        children: [new Paragraph({
          children: [new TextRun({ text: h, bold: true, color: COLOR.white, size: 20 })],
          alignment: AlignmentType.CENTER,
        })],
        shading: { type: ShadingType.SOLID, color: COLOR.teal },
        width: { size: colWidths ? colWidths[i] : Math.floor(9000 / headers.length), type: WidthType.DXA },
        margins: { top: 80, bottom: 80, left: 100, right: 100 },
      })
    ),
  });

  const dataRows = rows.map((row, ri) =>
    new TableRow({
      children: row.map((cell, ci) =>
        new TableCell({
          children: [new Paragraph({
            children: [new TextRun({ text: String(cell), size: 20 })],
          })],
          shading: { type: ShadingType.SOLID, color: ri % 2 === 0 ? COLOR.white : COLOR.lightGray },
          width: { size: colWidths ? colWidths[ci] : Math.floor(9000 / row.length), type: WidthType.DXA },
          margins: { top: 60, bottom: 60, left: 100, right: 100 },
        })
      ),
    })
  );

  return new Table({
    rows: [headerRow, ...dataRows],
    width: { size: 9000, type: WidthType.DXA },
    layout: TableLayoutType.FIXED,
  });
}

// ─── Document ────────────────────────────────────────────────────────────────

const doc = new Document({
  numbering: {
    config: [{
      reference: 'bullets',
      levels: [{ level: 0, format: LevelFormat.BULLET, text: '\u2022', alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }],
    }],
  },
  styles: {
    paragraphStyles: [
      {
        id: 'Normal', name: 'Normal', basedOn: 'Normal', next: 'Normal',
        run: { font: 'Calibri', size: 22, color: COLOR.black },
        paragraph: { spacing: { line: 276 } },
      },
      {
        id: 'Heading1', name: 'Heading1', basedOn: 'Normal',
        run: { font: 'Calibri', bold: true, size: 36, color: COLOR.teal },
        paragraph: { spacing: { before: 400, after: 160 } },
      },
      {
        id: 'Heading2', name: 'Heading2', basedOn: 'Normal',
        run: { font: 'Calibri', bold: true, size: 28, color: COLOR.accent },
        paragraph: { spacing: { before: 320, after: 120 } },
      },
      {
        id: 'Heading3', name: 'Heading3', basedOn: 'Normal',
        run: { font: 'Calibri', bold: true, size: 24, color: COLOR.gray },
        paragraph: { spacing: { before: 240, after: 80 } },
      },
    ],
  },
  sections: [{
    properties: {
      page: {
        margin: { top: convertInchesToTwip(1), bottom: convertInchesToTwip(1),
                  left: convertInchesToTwip(1.2), right: convertInchesToTwip(1.2) },
      },
    },
    children: [

      // ══════════════════════════════════════════════
      //  PAGE DE TITRE
      // ══════════════════════════════════════════════
      new Paragraph({
        children: [new TextRun({ text: '', break: 4 })],
      }),
      new Paragraph({
        children: [new TextRun({
          text: 'RAPPORT DE PROJET DE FIN D\'ÉTUDES',
          bold: true, size: 48, color: COLOR.teal,
        })],
        alignment: AlignmentType.CENTER,
        spacing: { after: 200 },
      }),
      new Paragraph({
        children: [new TextRun({
          text: 'Système de Supervision Énergétique Intelligente',
          bold: true, size: 36, color: COLOR.accent,
        })],
        alignment: AlignmentType.CENTER,
        spacing: { after: 160 },
      }),
      new Paragraph({
        children: [new TextRun({
          text: 'KOFERT Energy Dashboard',
          bold: true, size: 32, color: COLOR.gray,
        })],
        alignment: AlignmentType.CENTER,
        spacing: { after: 600 },
      }),
      new Paragraph({
        children: [new TextRun({ text: '─────────────────────────────────────', color: COLOR.teal, size: 28 })],
        alignment: AlignmentType.CENTER,
        spacing: { after: 400 },
      }),
      new Paragraph({
        children: [new TextRun({ text: 'Application Web Flutter — Firebase — Prévision Energitique', size: 24, color: COLOR.gray })],
        alignment: AlignmentType.CENTER,
        spacing: { after: 800 },
      }),
      new Paragraph({
        children: [new TextRun({ text: 'Déployé sur : https://ocp-energy-monitor.web.app', size: 22, color: COLOR.teal })],
        alignment: AlignmentType.CENTER,
        spacing: { after: 400 },
      }),
      new Paragraph({
        children: [new TextRun({ text: 'Mai 2026', size: 24, bold: true })],
        alignment: AlignmentType.CENTER,
        spacing: { after: 200 },
      }),

      pageBreak(),

      // ══════════════════════════════════════════════
      //  SOMMAIRE
      // ══════════════════════════════════════════════
      h1('Table des Matières'),
      separator(),
      ...[
        ['1.', 'Contexte et Problématique'],
        ['2.', 'Présentation Générale du Projet'],
        ['3.', 'Architecture Technique'],
        ['4.', 'Fonctionnalités Développées'],
        ['5.', "Module d'Intelligence Artificielle — Prévision Energitique"],
        ['6.', 'Sécurité et Contrôle d\'Accès'],
        ['7.', 'Infrastructure et Déploiement'],
        ['8.', 'Service de Rapport Automatique'],
        ['9.', 'Internationalisation'],
        ['10.', 'Résultats et Bilan'],
        ['11.', 'Conclusion'],
      ].map(([num, title]) =>
        new Paragraph({
          children: [
            new TextRun({ text: `${num}  `, bold: true, size: 22, color: COLOR.teal }),
            new TextRun({ text: title, size: 22 }),
          ],
          spacing: { after: 100 },
          indent: { left: 360 },
        })
      ),

      pageBreak(),

      // ══════════════════════════════════════════════
      //  1. CONTEXTE ET PROBLÉMATIQUE
      // ══════════════════════════════════════════════
      h1('1. Contexte et Problématique'),
      separator(),
      para(
        "Dans un contexte industriel marqué par la montée des coûts énergétiques et les exigences " +
        "croissantes en matière d'efficacité, KOFERT a exprimé le besoin d'un système de surveillance " +
        "énergétique en temps réel capable de superviser plusieurs unités industrielles de manière centralisée."
      ),
      mixedPara([
        new TextRun({ text: 'Problématique : ', bold: true, size: 22, color: COLOR.teal }),
        new TextRun({
          text: "Comment concevoir et déployer une application web performante permettant de mesurer, visualiser, " +
            "analyser et prédire la consommation énergétique de plusieurs équipements industriels hétérogènes " +
            "(AC/DC), tout en garantissant un accès sécurisé selon les rôles des utilisateurs, et en permettant " +
            "des exports et rapports automatisés ?",
          size: 22,
        }),
      ]),

      // ══════════════════════════════════════════════
      //  2. PRÉSENTATION GÉNÉRALE
      // ══════════════════════════════════════════════
      h1('2. Présentation Générale du Projet'),
      separator(),
      para(
        "Le projet KOFERT Energy Dashboard est une application web de supervision énergétique développée avec " +
        "Flutter Web et hébergée sur Firebase. Elle supervise en temps réel trois unités industrielles distinctes :"
      ),
      makeTable(
        ['Unité', 'Type', 'Matériel', 'Mesures'],
        [
          ['KOFERT_Unit_1', 'Charge AC', 'PZEM-004T', 'Tension 220V, courant, puissance, énergie, fréquence, cos φ'],
          ['KOFERT_Unit_2', 'Ventilateur DC 5V', 'INA219', 'Tension, courant (mA), puissance (mW), vitesse ventilateur (%)'],
          ['KOFERT_Unit_3', 'Pompe DC 5V', 'INA219', 'Tension, courant (mA), puissance (mW), niveau d\'eau (%)'],
        ],
        [1800, 1800, 1800, 3600]
      ),
      new Paragraph({ text: '', spacing: { after: 160 } }),
      mixedPara([
        new TextRun({ text: "URL de production : ", bold: true, size: 22 }),
        new TextRun({ text: "https://ocp-energy-monitor.web.app", size: 22, color: COLOR.teal,
          underline: { type: UnderlineType.SINGLE } }),
      ]),

      // ══════════════════════════════════════════════
      //  3. ARCHITECTURE TECHNIQUE
      // ══════════════════════════════════════════════
      pageBreak(),
      h1('3. Architecture Technique'),
      separator(),

      h2('3.1 Stack Technologique'),
      makeTable(
        ['Couche', 'Technologie', 'Rôle'],
        [
          ['Frontend', 'Flutter Web (Dart 3.x)', 'Interface utilisateur réactive et multiplateforme'],
          ['Temps réel', 'Firebase Realtime Database', 'Stream WebSocket des métriques live'],
          ['Persistance', 'Cloud Firestore (NoSQL)', 'Historique time-series, rôles, chat, alertes'],
          ['Auth', 'Firebase Authentication', 'Email/mot de passe + vérification email'],
          ['Hébergement', 'Firebase Hosting (CDN)', 'Déploiement HTTPS mondial'],
          ['Email', 'EmailJS REST API', 'Rapports HTML automatisés'],
          ['Graphiques', 'Syncfusion Flutter Charts', 'Courbes temps réel et historiques'],
          ['Export', 'Package excel (Dart)', 'Génération .xlsx côté client'],
          ['Cache', 'SharedPreferences', 'Disponibilité offline des dernières valeurs'],
        ],
        [2000, 2500, 4500]
      ),
      new Paragraph({ text: '', spacing: { after: 160 } }),

      h2('3.2 Architecture des Données'),
      para("Le projet utilise deux bases de données Firebase de manière complémentaire :"),

      h3('Firebase Realtime Database — Données temps réel'),
      codePara('{unitId}/current_metrics      → lecture live (stream WebSocket)'),
      codePara('{unitId}/fan_control          → commande vitesse ventilateur'),
      codePara('{unitId}/pump_control         → commande relais pompe'),

      h3('Cloud Firestore — Historique et persistance'),
      codePara('sensor_readings/{id}    → 1 doc/minute/unité (time-series)'),
      codePara('unit_status/{unitId}    → snapshot le plus récent'),
      codePara('maintenance_logs/{id}   → journal des interventions'),
      codePara('users/{uid}             → profils utilisateurs + rôles RBAC'),
      codePara('global_chat/{msgId}     → messagerie globale'),
      codePara('dm_chats/{chatId}       → messages directs (participants)'),
      codePara('invitations/{invId}     → invitations de rôle'),
      codePara('alerts/{alertId}        → historique des alertes'),

      // ══════════════════════════════════════════════
      //  4. FONCTIONNALITÉS
      // ══════════════════════════════════════════════
      pageBreak(),
      h1('4. Fonctionnalités Développées'),
      separator(),

      h2('4.1 Tableau de Bord Temps Réel'),
      para("Le dashboard affiche en temps réel les métriques de l'unité sélectionnée via un stream Firebase Realtime Database :"),
      bullet('Jauges visuelles Syncfusion : tension, courant, facteur de puissance'),
      bullet('Valeurs numériques : puissance active (W/mW), énergie cumulée, fréquence'),
      bullet('Contrôle actif : curseur de vitesse ventilateur (Unit_2), toggle relais pompe (Unit_3)'),
      bullet("Système d'alertes dynamiques : seuils configurables (surtension, sous-tension, courant excessif, cos φ bas)"),
      bullet('Horloge temps réel + statut de connexion Firebase'),
      bullet('Cache offline via SharedPreferences (maintien des dernières valeurs en cas de perte réseau)'),
      bullet('Debounce 1 seconde sur les mises à jour UI pour éviter le re-rendu excessif'),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('4.2 Écran Historique'),
      para("L'écran historique offre une analyse approfondie des données passées :"),
      h3('Visualisation :'),
      bullet("Graphique en courbe (Syncfusion LineChart) avec sélection de métrique : Puissance (W/mW), Courant (A/mA), Tension, Énergie, Facteur de puissance, Fréquence"),
      bullet("Conversion d'unités automatique : affichage en mW/mA pour les unités DC (Unit_2, Unit_3) et W/A pour l'unité AC (Unit_1)"),
      bullet("Filtrage par plage de dates (date début / date fin)"),
      bullet("Vue toutes unités (ALL_UNITS) : agrégation multi-unités sur un seul graphique"),
      h3('Export des données :'),
      bullet("Export CSV : toutes les mesures de la période, avec en-têtes dynamiques (mW/mA pour DC)"),
      bullet("Export Excel (.xlsx) : formaté avec colonnes typées (DoubleCellValue), mêmes unités adaptées"),
      bullet("Export automatique déclenché lors de l'envoi d'email"),
      h3('Rapports Email (EmailJS) :'),
      bullet("Facture énergétique : énergie totale, tarif (MAD/mWh), coût estimé, projections mensuelles"),
      bullet("Prévision Energitique : énergie prévue J+1, J+7, J+30 ; coût mensuel prévu ; niveau de confiance (%)"),
      bullet("Tableau de données : 20 échantillons avec horodatage, puissance, tension, courant, cos φ"),
      bullet("Colonne « Unité » si la vue ALL_UNITS est active"),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('4.3 Écran Comparaison'),
      bullet("Vue côte-à-côte des 3 unités simultanément"),
      bullet("Graphiques historiques (puissance, tension, courant) avec fenêtre glissante de 60 points"),
      bullet("Flux temps réel sur les 3 unités en parallèle"),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('4.4 Écran Synthèse'),
      bullet("Onglet Journalier : énergie consommée par jour, coût journalier, statut de chaque unité"),
      bullet("Onglet Mensuel : totalisation mensuelle, coûts cumulés, tendances"),
      bullet("Tarif configurable depuis l'écran Paramètres"),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('4.5 Gestion de la Maintenance'),
      bullet("Journal des interventions techniques (CRUD complet)"),
      bullet("Filtres par unité et par statut (en attente / résolu)"),
      bullet("Accès restreint aux rôles opérateur et admin"),
      bullet("Intégration avec le système de notifications"),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('4.6 Historique des Alertes'),
      bullet("Fusion : alertes de session (en mémoire) + alertes persistées dans Firestore"),
      bullet("Déduplication intelligente : par triplet (titre + unitId + minute arrondie)"),
      bullet("Types d'alertes : bas cos φ, surtension, sous-tension, surintensité, bas niveau d'eau"),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('4.7 Messagerie Intégrée'),
      bullet("Chat Global : salle commune accessible à tous les utilisateurs authentifiés"),
      bullet("Messages Directs : conversations privées (chemin Firestore : dm_chats/{uid1_uid2}/messages)"),
      bullet("Liste d'utilisateurs : statut de présence en temps réel (en ligne / hors ligne / DND)"),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('4.8 Paramètres Configurables'),
      makeTable(
        ['Paramètre', 'Description'],
        [
          ['Tarif (MAD/mWh)', 'Taux de facturation, défaut : 1,15 MAD/mWh'],
          ['Seuils de tension', 'Haut/bas pour déclenchement alerte'],
          ['Seuil de courant', 'Maximum admissible'],
          ['Seuil cos φ', 'Valeur minimale acceptable'],
          ['Auto-refresh', 'Intervalle de rafraîchissement automatique (secondes)'],
          ['Thème', 'Sombre / Clair / Système'],
          ['Langue', 'Français / Anglais / Arabe'],
          ['Rapport automatique', 'Activé, fréquence (journalier/hebdomadaire), email destinataire'],
        ],
        [3000, 6000]
      ),

      // ══════════════════════════════════════════════
      //  5. MODULE IA
      // ══════════════════════════════════════════════
      pageBreak(),
      h1("5. Module d'Intelligence Artificielle — Prévision Energitique"),
      separator(),

      h2('5.1 Modèle Utilisé'),
      para(
        "Le module EnergyPredictor implémente une régression linéaire sur les données historiques " +
        "stockées dans Firestore. Ce choix est justifié par :"
      ),
      bullet("La nature des séries temporelles de consommation électrique"),
      bullet("La légèreté computationnelle (côté client, sans serveur)"),
      bullet("La transparence et l'interprétabilité des résultats"),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('5.2 Prévisions Générées'),
      makeTable(
        ['Prévision', 'Description'],
        [
          ['Énergie J+1', 'Énergie prévue sur les 24 prochaines heures (mWh)'],
          ['Coût J+1', 'nextDayEnergyMwh × tarif (MAD)'],
          ['Énergie J+7', 'nextDayEnergyMwh × 7'],
          ['Énergie J+30', 'nextDayEnergyMwh × 30'],
          ['Coût fin de mois', 'Coût mensuel cumulé + prévision jours restants'],
          ['Cos φ dans 10 min', 'Valeur prédite via régression sur les 60 dernières mesures'],
          ['Tendance cos φ', 'Montante / Stable / Descendante (seuil : ±0.001/lecture)'],
          ['Alerte chute cos φ', 'Alerte si la valeur va passer sous le seuil dans les 10 prochaines minutes'],
        ],
        [2800, 6200]
      ),
      new Paragraph({ text: '', spacing: { after: 160 } }),

      h2('5.3 Niveau de Confiance'),
      codePara('Confiance coût  = min(1.0, nb_lectures / 200)   → 100% dès 200 lectures'),
      codePara('Confiance cos φ = R² de la régression linéaire'),
      new Paragraph({ text: '', spacing: { after: 120 } }),
      para(
        "Grâce aux 19 200 données historiques injectées dans Firestore (simulation sur 30 jours, " +
        "intervalle 5 minutes), chaque unité dispose de ~6 400 lectures, garantissant un niveau de " +
        "confiance de 100% pour toutes les prévisions de coût."
      ),

      h2('5.4 Données de Simulation'),
      makeTable(
        ['Unité', 'Profil de charge', 'Particularités'],
        [
          ['Unit_1 (AC)', 'Pic 70-100% heures ouvrées (8h-12h, 14h-18h), nuit 5-20%', 'Énergie cumulative, fréquence 50 Hz'],
          ['Unit_2 (DC Fan)', 'Vitesse variable selon charge', "Champ fanSpeed (%)"],
          ['Unit_3 (DC Pump)', 'Niveau d\'eau fluctuant 65 ± 10%', 'Champ waterLevel (%)'],
        ],
        [1800, 4200, 3000]
      ),

      // ══════════════════════════════════════════════
      //  6. SÉCURITÉ
      // ══════════════════════════════════════════════
      pageBreak(),
      h1("6. Sécurité et Contrôle d'Accès"),
      separator(),

      h2('6.1 Authentification'),
      bullet("Firebase Authentication : email/mot de passe avec vérification d'email obligatoire"),
      bullet("Gestion des sessions, renouvellement automatique des tokens JWT"),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('6.2 Modèle RBAC (Role-Based Access Control)'),
      makeTable(
        ['Rôle', 'Droits'],
        [
          ['admin', 'Accès total, suppression, gestion de tous les rôles'],
          ['moderator', 'Gestion des utilisateurs (promotion jusqu\'à modérateur), modération du chat'],
          ['operator', 'Écriture sensor_readings, unit_status, maintenance_logs'],
          ['observer', 'Lecture de toutes les données'],
          ['viewer', 'Lecture basique'],
        ],
        [2000, 7000]
      ),
      new Paragraph({ text: '', spacing: { after: 160 } }),

      h2('6.3 Règles Firestore (Security Rules)'),
      para("Les règles sont déclaratives et évaluées côté serveur Google Cloud :"),
      codePara('function isAdmin()    { return isSignedIn() && role() == "admin"; }'),
      codePara('function isOperator() { return isSignedIn() && role() in ["admin","moderator","operator"]; }'),
      codePara(''),
      codePara('match /sensor_readings/{id} {'),
      codePara('  allow read:   if isAnyUser();'),
      codePara('  allow create: if isOperator()'),
      codePara('    && request.resource.data.keys().hasAll(["unitId","timestamp","voltage","current"])'),
      codePara('    && request.resource.data.unitId in ["KOFERT_Unit_1","KOFERT_Unit_2","KOFERT_Unit_3"];'),
      codePara('  allow update, delete: if isAdmin();'),
      codePara('}'),

      // ══════════════════════════════════════════════
      //  7. INFRASTRUCTURE ET DÉPLOIEMENT
      // ══════════════════════════════════════════════
      pageBreak(),
      h1('7. Infrastructure et Déploiement'),
      separator(),

      h2('7.1 Firebase Hosting'),
      bullet('URL production : https://ocp-energy-monitor.web.app'),
      bullet('index.html + Service Worker : no-cache (toujours à jour)'),
      bullet('Assets statiques (JS/CSS/fonts) : 1 an de cache immuable'),
      bullet('En-tête sécurité : X-Frame-Options: SAMEORIGIN'),
      new Paragraph({ text: '', spacing: { after: 80 } }),

      h2('7.2 Processus de Déploiement'),
      codePara('# 1. Build Flutter Web'),
      codePara('flutter build web --release'),
      codePara(''),
      codePara('# 2. Déploiement Firebase'),
      codePara('npx firebase-tools deploy --only hosting,firestore:rules,firestore:indexes'),
      new Paragraph({ text: '', spacing: { after: 120 } }),

      h2('7.3 Indexes Firestore'),
      para("Index composites optimisés pour les requêtes de séries temporelles :"),
      codePara('sensor_readings : unitId ASC + timestamp DESC  (requêtes historiques)'),
      codePara('sensor_readings : unitId ASC + timestamp ASC   (export chronologique)'),
      new Paragraph({ text: '', spacing: { after: 120 } }),

      h2('7.4 Firebase Data Connect (PostgreSQL)'),
      para(
        "Le projet intègre également Firebase Data Connect (schéma GraphQL sur PostgreSQL) pour une couche " +
        "de données structurée avec types stricts (EnergyUnit, EnergyMetric, EnergyAlert) — infrastructure " +
        "complémentaire au Firestore NoSQL."
      ),

      // ══════════════════════════════════════════════
      //  8. RAPPORT AUTOMATIQUE
      // ══════════════════════════════════════════════
      pageBreak(),
      h1('8. Service de Rapport Automatique'),
      separator(),
      para("Le service AutoReportService envoie automatiquement des rapports périodiques par email via EmailJS :"),
      makeTable(
        ['Paramètre', 'Valeur'],
        [
          ['Service EmailJS', 'service_1tovyp1'],
          ['Template', 'template_9cy6uou'],
          ['Déclenchement', 'Timer horaire (vérifie fréquence configurée)'],
          ['Fréquences', 'Journalier / Hebdomadaire'],
          ['Contenu', 'Tableau HTML : puissance moy., cos φ moy., énergie totale, coût estimé'],
        ],
        [3000, 6000]
      ),

      // ══════════════════════════════════════════════
      //  9. INTERNATIONALISATION
      // ══════════════════════════════════════════════
      h1('9. Internationalisation'),
      separator(),
      para("L'application supporte trois langues via flutter_localizations et fichiers ARB :"),
      bullet('🇫🇷 Français (par défaut)'),
      bullet('🇬🇧 Anglais'),
      bullet('🇸🇦 Arabe'),
      para("Le changement de langue est dynamique sans rechargement de l'application (languageNotifier)."),

      // ══════════════════════════════════════════════
      //  10. RÉSULTATS ET BILAN
      // ══════════════════════════════════════════════
      pageBreak(),
      h1('10. Résultats et Bilan'),
      separator(),
      makeTable(
        ['Critère', 'Résultat'],
        [
          ['Application déployée en production', '✅  https://ocp-energy-monitor.web.app'],
          ['Supervision temps réel 3 unités', '✅  WebSocket Firebase Realtime Database'],
          ['Historique Firestore (time-series)', '✅  19 200 documents injectés'],
          ['Prévision Energitique (confiance 100%)', '✅  Régression linéaire opérationnelle'],
          ['Exports CSV et Excel', '✅  Téléchargement navigateur côté client'],
          ['Rapports email HTML automatisés', '✅  EmailJS + facture + Prévision Energitique'],
          ["Contrôle d'accès RBAC complet", '✅  5 rôles, règles Firestore déployées'],
          ['Messagerie intégrée', '✅  Chat global + DM + présence temps réel'],
          ['Multilingue (FR / EN / AR)', '✅  flutter_localizations opérationnel'],
          ['Responsive Web (Flutter Web)', '✅  Interface adaptative sur tous les navigateurs'],
        ],
        [4500, 4500]
      ),

      // ══════════════════════════════════════════════
      //  11. CONCLUSION
      // ══════════════════════════════════════════════
      pageBreak(),
      h1('11. Conclusion'),
      separator(),
      para(
        "Ce projet de fin d'études a permis de concevoir et déployer de bout en bout un système de supervision " +
        "énergétique industrielle complet, en mettant en œuvre des technologies modernes du développement web " +
        "full-stack. Le tableau ci-dessous résume les compétences techniques acquises et mises en œuvre :"
      ),
      makeTable(
        ['Domaine', 'Compétences / Technologies'],
        [
          ['Frontend', 'Flutter Web, Dart 3.x, Syncfusion Charts & Gauges, Material Design'],
          ['Backend / BaaS', 'Firebase Auth, Realtime Database, Cloud Firestore, Data Connect'],
          ['Sécurité', 'RBAC, Security Rules Firestore, JWT Firebase, vérification email'],
          ['Machine Learning', 'Régression linéaire, prévisions de séries temporelles, calcul R²'],
          ['Intégrations', 'EmailJS REST API, Excel package, QR codes, SharedPreferences'],
          ['DevOps', 'Firebase CLI, build Flutter Web, CDN Hosting, indexes Firestore'],
          ['UX/UI', 'Thème sombre personnalisé, multilingue, responsive, jauges temps réel'],
        ],
        [2500, 6500]
      ),
      new Paragraph({ text: '', spacing: { after: 200 } }),
      para(
        "Le système répond pleinement aux besoins exprimés par KOFERT : centralisation de la supervision, " +
        "réduction des interventions manuelles grâce aux alertes automatiques, anticipation des dérives " +
        "énergétiques par la Prévision Energitique, et traçabilité complète via les rapports email et exports Excel."
      ),
      new Paragraph({
        children: [new TextRun({ text: '', break: 2 })],
      }),
      new Paragraph({
        children: [new TextRun({
          text: 'Rapport de Projet de Fin d\'Études — KOFERT Energy Dashboard — Mai 2026',
          size: 18, color: COLOR.gray, italics: true,
        })],
        alignment: AlignmentType.CENTER,
      }),
    ],
  }],
});

// ─── Write file ──────────────────────────────────────────────────────────────

const outPath = path.join(__dirname, 'PFE_Rapport_KOFERT_Energy_Dashboard.docx');

Packer.toBuffer(doc).then((buffer) => {
  fs.writeFileSync(outPath, buffer);
  console.log('✅  Rapport généré avec succès !');
  console.log('📄  Fichier : ' + outPath);
}).catch(err => {
  console.error('❌  Erreur :', err.message);
});
