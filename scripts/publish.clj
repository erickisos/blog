#!/usr/bin/env bb

(require '[babashka.fs :as fs]
         '[babashka.http-client :as http]
         '[cheshire.core :as json]
         '[clojure.string :as str])

;; ============================================================
;; Pure functions (easily testable)
;; ============================================================

(defn- line->kv
  "Parse a str into a key-value pair using a colon as separator"
  [line]
  (when-let [[_ k v] (re-matches #"^(\w+):\s*(.*)$" line)]
    [(-> k str/lower-case str/trim keyword)
     (str/trim v)]))

(defn- frontmatter->metadata
  "Transform a list of frontmatter lines to a metadata EDN."
  [lines]
  (->> lines
       (map line->kv)
       (into {})))

(defn- metadata->tags
  "Extract the tags field from the metadata map"
  [metadata]
  (let [tags (get metadata :tags "")]
    (->> (str/split tags #",")
         (map str/trim)
         (map str/lower-case)
         (remove str/blank?))))

(defn- unquote-string
  "Remove surrounding quotes from a string if present"
  [s]
  (when s
    (or (second (re-matches #"^[\"'](.*)[\"']$" s))
        s)))

(defn- metadata->title
  "Extract title from metadata and remove quotes if present"
  [metadata]
  (-> metadata
      :title
      unquote-string))

(defn- metadata->description
  [metadata]
  (:description metadata))

(defn- split-frontmatter
  "Divide the lines into frontmatter and content lines."
  [lines]
  (if-let [[frontmatter-lines content] (and (> (count lines) 2)
                                            (= (first lines) "---")
                                            (split-with #(not= "---" %) (rest lines)))]
    [(frontmatter->metadata frontmatter-lines) (rest content)]
    [{} lines]))

(defn- read-markdown
  "Extract the frontmatter and content of a given file."
  [file]
  (-> file
      str
      slurp
      str/split-lines
      split-frontmatter))

;; ============================================================
;; I/O functions (side effects)
;; ============================================================
(defn spy!
  [& args]
  (println args)
  args)

(defn- get-api-key
  "Get DEVTO_API_KEY from environment"
  []
  (System/getenv "DEVTO_API_KEY"))

(defn- file->article
  "Reads a markdown file and parse the content to a valid article"
  [file]
  (let [[metadata content] (read-markdown file)]
    {:title       (metadata->title metadata)
     :description (metadata->description metadata)
     :tags        (metadata->tags metadata)
     :filename    (fs/file-name file)
     :body        (str/join "\n" content)}))

(defn get-articles!
  "Fetch all existing articles from Dev.to API"
  [api-key]
  (try
    (-> "https://dev.to/api/articles/me/all"
        (http/get {:headers      {"api-key" api-key}
                   :query-params {"per_page" 1000}})
        :body
        (json/parse-string true))
    (catch Exception _
      (println "⚠️ Advertencia: No se pudieron obtener artículos existentes")
      [])))

(defn- build-payload
  "Build Dev.to API payload from article data"
  [article]
  {:article {:title         (:title article)
             :body_markdown (:body article)
             :description   (:description article)
             :published     false
             :tags          (:tags article)}})

(defn- find-article-id [all-articles article]
  (some #(when (= (:title %) (:title article)) (:id %)) all-articles))

(defn- api-call
  "Generic API call handler with error wrapping"
  [http-fn url options]
  (try
    {:success true
     :data (-> (http-fn url options)
               :body
               (json/parse-string true))}
    (catch Exception e
      (println (str "❌ Hubo un fallo al intentar ejecutar la llamada " http-fn " a la URL: " url ", with options: " options ", error: " e))
      {:success false
       :error (.getMessage e)})))

(defn create-article!
  "Post a new article to dev.to"
  [article api-key]
  (let [result (api-call http/post
                         "https://dev.to/api/articles"
                         {:headers {"api-key"      api-key
                                    "Content-Type" "application/json"}
                          :body    (json/generate-string (build-payload article))})]
    (if (:success result)
      {:status :created :url (-> result :data :url)}
      {:status :failed :error (:error result)})))

(defn update-article!
  "Update a given article by id in dev.to"
  [id article api-key]
  (let [result (api-call http/put
                         (str "https://dev.to/api/articles/" id)
                         {:headers {"api-key"      api-key
                                    "Content-Type" "application/json"}
                          :body    (json/generate-string (build-payload article))})]
    (if (:success result)
      {:status :updated :url (-> result :data :url)}
      {:status :failed :error (:error result)})))

(defn publish-article!
  [article articles api-key]
  (if-let [id (find-article-id article articles)]
    (update-article! id article api-key)
    (create-article! article api-key)))

;; ============================================================
;; Main entry point
;; ============================================================

(defn- main [& _args]
  (let [script-dir   (fs/parent *file*)
        project-root (fs/parent script-dir)
        files        (fs/glob (fs/file project-root "build") "*.md")
        api-key      (get-api-key)
        all-articles (get-articles! api-key)
        publish!     #(publish-article! % all-articles api-key)
        results      (->> files
                          (map file->article)
                          (map publish!)
                          doall)
        created      (->> results (filter #(= (:status %) :created)) count)
        updated      (->> results (filter #(= (:status %) :updated)) count)
        failed       (->> results (filter #(= (:status %) :failed)) count)]
    (println "📊 Resumen:")
    (println (str "   ➕ Creados: " created))
    (println (str "   🔄 Actualizados: " updated))
    (println (str "   ❌ Fallidos: " failed))
    (when (pos? failed) (System/exit 1))))

(when (= *file* (System/getProperty "babashka.file"))
  (apply main *command-line-args*))
