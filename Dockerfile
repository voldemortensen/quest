FROM node:26

WORKDIR /app
COPY ./ /app
RUN npm install

CMD ["node", "src/000.js"]


