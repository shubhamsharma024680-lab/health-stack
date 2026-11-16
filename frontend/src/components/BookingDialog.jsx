import { useState } from "react";
import { useNavigate } from "react-router-dom";
import * as api from "../api/index.js";
import { useToast } from "../context/ToastContext.jsx";
import { useRemote } from "../hooks/useRemote.js";
import { fmtDate, hospitalToday } from "../lib/clock.js";
import { inr } from "../lib/money.js";
import { Dialog } from "./Dialog.jsx";
import { DateChoice, SlotPicker } from "./SlotPicker.jsx";
import { Button, Field, InlineError, Select } from "./ui.jsx";

const SLOT_TAKEN = "This slot was just booked. Choose another time.";

// Patient books a visit: department → doctor → date → available slot.
export function BookingDialog({ initialDoctorId = "", initialDate, initialTime = "", onClose }) {
  const toast = useToast();
  const navigate = useNavigate();
  const data = useRemote(() => Promise.all([api.listDepartments(), api.listDoctors()]), "booking");
  const [departments, doctors] = data.data || [[], []];
  const preset = doctors.find((d) => String(d.id) === String(initialDoctorId));
  const [form, setForm] = useState({ departmentId: null, doctorId: String(initialDoctorId || ""), date: initialDate || hospitalToday(), time: initialTime });
  const departmentId = form.departmentId ?? (preset ? String(preset.departmentId) : "");
  const [errors, setErrors] = useState({});
  const [formError, setFormError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const dirty = form.time !== initialTime || form.doctorId !== String(initialDoctorId || "");
  const doctor = doctors.find((d) => String(d.id) === form.doctorId);
  const choices = doctors.filter((d) => !departmentId || String(d.departmentId) === departmentId);

  const set = (patch) => { setForm((f) => ({ ...f, ...patch })); setErrors({}); setFormError(null); };

  const submit = async (e) => {
    e.preventDefault();
    const next = {};
    if (!departmentId) next.departmentId = "Select a department.";
    if (!form.doctorId) next.doctorId = "Select a doctor.";
    if (!form.time) next.time = "Select an available time.";
    setErrors(next);
    if (Object.keys(next).length) return;
    setBusy(true);
    setFormError(null);
    try {
      const result = await api.bookAppointment(form);
      toast("Appointment booked.");
      onClose();
      navigate(`/appointments/${result.appointment_id}`);
    } catch (err) {
      // Keep every other field; refresh the slots so the patient can choose again.
      // Someone else took the slot: say so plainly. Any other 409 (for example the
      // patient already has a visit at that time) shows the server's own message.
      setFormError(err.status === 409 && /occupied/i.test(err.message) ? SLOT_TAKEN : err.message);
      setForm((f) => ({ ...f, time: "" }));
      setRefreshKey((k) => k + 1);
      setBusy(false);
    }
  };

  return (
    <Dialog title="Book appointment" description="Bookings are open for today and the next 3 days." size="lg" onClose={onClose} dirty={dirty} busy={busy}
      footer={({ requestClose }) => (
        <>
          <Button variant="secondary" onClick={requestClose} disabled={busy}>Cancel</Button>
          <Button type="submit" form="booking-form" pending={busy} pendingLabel="Booking…">Book appointment</Button>
        </>
      )}>
      {data.error && !data.data ? (
        <InlineError>{data.error.message}</InlineError>
      ) : (
        <form id="booking-form" onSubmit={submit} noValidate className="space-y-5">
          <InlineError>{formError}</InlineError>
          <div className="grid sm:grid-cols-2 gap-4">
            <Field label="Department" required error={errors.departmentId}>
              <Select value={departmentId} disabled={data.loading} onChange={(e) => set({ departmentId: e.target.value, doctorId: "", time: "" })}>
                <option value="">{data.loading ? "Loading…" : "Select department"}</option>
                {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
              </Select>
            </Field>
            <Field label="Doctor" required error={errors.doctorId} helper={departmentId ? undefined : "Choose a department first."}>
              <Select value={form.doctorId} disabled={!departmentId} onChange={(e) => set({ doctorId: e.target.value, time: "" })}>
                <option value="">Select doctor</option>
                {choices.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
              </Select>
            </Field>
          </div>
          <DateChoice value={form.date} onChange={(date) => set({ date, time: "" })} />
          <SlotPicker doctorId={form.doctorId} date={form.date} value={form.time} onChange={(time) => set({ time })} error={errors.time} refreshKey={refreshKey} />
          {doctor && (
            <p className="bg-surface-blue rounded-[10px] p-3">
              {doctor.name} · {doctor.department} · Consultation fee <span className="tabular-nums font-semibold">{inr(doctor.feePaise)}</span>
              {form.time && <> · <span className="tabular-nums">{fmtDate(form.date, { weekday: true })}, {form.time}</span></>}
            </p>
          )}
        </form>
      )}
    </Dialog>
  );
}

// Patient moves a future visit to another slot with the same doctor. The ID is kept.
export function RescheduleDialog({ appointment, onClose, onDone }) {
  const [date, setDate] = useState(hospitalToday());
  const [time, setTime] = useState("");
  const [error, setError] = useState(null);
  const [fieldError, setFieldError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  const submit = async (e) => {
    e.preventDefault();
    if (!time) { setFieldError("Select an available time."); return; }
    setBusy(true);
    setError(null);
    try {
      await api.rescheduleAppointment(appointment.id, { date, time });
      onDone();
    } catch (err) {
      setError(err.status === 409 && /occupied/i.test(err.message) ? SLOT_TAKEN : err.message);
      setTime("");
      setRefreshKey((k) => k + 1);
      setBusy(false);
    }
  };

  return (
    <Dialog title="Reschedule appointment" description={`${appointment.doctorName} · currently ${fmtDate(appointment.date, { weekday: true })}, ${appointment.time}`}
      size="lg" onClose={onClose} dirty={!!time} busy={busy}
      footer={({ requestClose }) => (
        <>
          <Button variant="secondary" onClick={requestClose} disabled={busy}>Cancel</Button>
          <Button type="submit" form="reschedule-form" pending={busy} pendingLabel="Saving…">Reschedule</Button>
        </>
      )}>
      <form id="reschedule-form" onSubmit={submit} noValidate className="space-y-5">
        <InlineError>{error}</InlineError>
        <DateChoice value={date} onChange={(d) => { setDate(d); setTime(""); setFieldError(null); }} />
        <SlotPicker doctorId={appointment.doctorId} date={date} value={time} onChange={(t) => { setTime(t); setFieldError(null); }} error={fieldError} refreshKey={refreshKey} />
      </form>
    </Dialog>
  );
}
