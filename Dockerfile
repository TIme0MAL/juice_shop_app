# Étape 1 : Installation des dépendances et préparation du projet
FROM node:20-buster AS installer

# Copier le code source dans le conteneur
COPY . /juice-shop
WORKDIR /juice-shop

# Ajouter la variable d'environnement NODE_OPTIONS pour allouer plus de mémoire à Node.js
ENV NODE_OPTIONS="--max-old-space-size=4096"

# Installer TypeScript et ts-node globalement
RUN npm i -g typescript ts-node

# Installer les dépendances en excluant les devDependencies et en utilisant des permissions non-sécurisées pour éviter des erreurs dans l'environnement de production
RUN npm install --omit=dev --unsafe-perm --legacy-peer-deps

# Dédoublonner les modules et nettoyer les dépendances inutiles
RUN npm dedupe --omit=dev

# Nettoyer des fichiers et dossiers inutiles pour réduire la taille de l'image
RUN rm -rf frontend/node_modules
RUN rm -rf frontend/.angular
RUN rm -rf frontend/src/assets

# Créer un dossier de logs et définir les permissions
RUN mkdir logs
RUN chown -R 65532 logs

# Modifier les permissions pour certains répertoires afin d'être accessibles par l'utilisateur non-root
RUN chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/
RUN chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/

# Supprimer des fichiers spécifiques dans le répertoire data, ftp, et i18n
RUN rm -f data/chatbot/botDefaultTrainingData.json || true
RUN rm -f ftp/legal.md || true
RUN rm -f i18n/*.json || true

# Installer CycloneDX pour générer un SBOM (Software Bill of Materials)
ARG CYCLONEDX_NPM_VERSION=latest
RUN npm install -g @cyclonedx/cyclonedx-npm@$CYCLONEDX_NPM_VERSION
RUN npm run sbom

# Étape 2 : Construction de libxmljs (solution de contournement pour l'erreur de démarrage)
FROM node:20-buster AS libxmljs-builder

# Installer les outils nécessaires pour la construction
WORKDIR /juice-shop
RUN apt-get update && apt-get install -y build-essential python3

# Copier les modules de l'étape précédente
COPY --from=installer /juice-shop/node_modules ./node_modules

# Nettoyer les fichiers de construction et reconstruire libxmljs
RUN rm -rf node_modules/libxmljs/build && \
    cd node_modules/libxmljs && \
    npm run build

# Étape 3 : Construire l'image finale avec une image distroless
FROM gcr.io/distroless/nodejs20-debian11

# Définir les métadonnées de l'image
ARG BUILD_DATE
ARG VCS_REF
LABEL maintainer="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
    org.opencontainers.image.title="OWASP Juice Shop" \
    org.opencontainers.image.description="Probably the most modern and sophisticated insecure web application" \
    org.opencontainers.image.authors="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
    org.opencontainers.image.vendor="Open Worldwide Application Security Project" \
    org.opencontainers.image.documentation="https://help.owasp-juice.shop" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.version="17.2.0" \
    org.opencontainers.image.url="https://owasp-juice.shop" \
    org.opencontainers.image.source="https://github.com/juice-shop/juice-shop" \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.created=$BUILD_DATE

# Définir le répertoire de travail
WORKDIR /juice-shop

# Copier le code et les fichiers depuis l'étape d'installation
COPY --from=installer --chown=65532:0 /juice-shop .

# Copier le module libxmljs compilé depuis l'étape de construction
COPY --chown=65532:0 --from=libxmljs-builder /juice-shop/node_modules/libxmljs ./node_modules/libxmljs

# Utiliser un utilisateur non-root pour exécuter l'application
USER 65532

# Exposer le port 3000 sur lequel l'application sera exécutée
EXPOSE 3000

# Commande pour démarrer l'application
CMD ["/juice-shop/build/app.js"]