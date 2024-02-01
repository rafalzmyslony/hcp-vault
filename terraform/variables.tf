variable "db_name" {
  description = "DB name for todo app"
  default     = "baza_danych"
}

variable "db_role_name" {
  description = "DB role name (user) for todo app"
  default     = "todo_uzytkownik"
}
variable "db_pass" {
  description = "DB password before changing for vault purposes"
  default     = "first_password"
}
variable "vault_role_name_to_db" {
  description = "This is role name for postgresql that is used by HCP Vault in database secret engine "
  default     = "vault_root"
}
variable "vault_pass_to_db" {
  description = "This is password for postgresql role used by HCP Vault in database secret engine "
  default     = "b@f_V,V5<r27"
}
